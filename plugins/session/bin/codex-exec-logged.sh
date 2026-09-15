#!/usr/bin/env bash
# codex-exec-logged.sh — a thin logging and context-composing wrapper around
# `codex exec`.
#
# Usage: codex-exec-logged.sh [--detach <done-file>] [--role <name>]
#                             [--prompt-file <path>] <codex exec args...> [-]
# The three wrapper options come first, in any order; everything after them is
# forwarded to `codex exec` verbatim with `--json` added, so the caller's flags
# (-m, -c, -s, -C, -o, --ephemeral, the trailing `-`) keep working unchanged.
# codex's exit code is the wrapper's exit code, and the answer still lands only
# in the `-o` file. `--role`, `--prompt-file` and `--detach` never reach codex.
#
# Context composition: when the prompt comes on stdin (trailing `-`) or from
# `--prompt-file <path>` (the wrapper then appends `-`), codex's stdin is built
# in memory as header-delimited sections, in this order; a missing or empty
# optional file drops its section and header:
#   [ROLE: <name>]       body of <script real dir>/../agents/<name>.md (no frontmatter)
#   [USER CLAUDE.md]     $HOME/.claude/CLAUDE.md
#   [PROJECT CLAUDE.md]  <codex cwd>/CLAUDE.md
#   [MEMORY INDEX]       $HOME/.claude/projects/<codex cwd, / and . as ->/memory/MEMORY.md
#   [RESPONSE STYLE]     codex-style.md next to this script (CODEX_STYLE_FILE overrides)
#   [TASK]               the caller's prompt
# codex cwd = the -C / --cd / --cd= value (relative to $PWD), else $PWD; logical
# path. The composed text is never written to disk.
#
# Exit codes of the wrapper itself (codex not started):
#   2   unknown role, agents dir not found, --role without - or --prompt-file
#   3   prompt file not found
#   127 codex not found on the inherited PATH
#
# CODEX_EXEC_DRY_RUN=1 prints the composed stdin and one line
# `CODEX ARGV: exec --json <args>` and exits 0; it never runs codex, never
# detaches and never writes the ledger (test hook).
#
# Side effect: one JSON line per run is appended to ~/.codex/proxy-usage.jsonl
#   {"ts","model","effort","input","cached_input","output","reasoning_output","label"}
# `label` comes from env CODEX_LABEL (empty string when unset). The claude-cost
# SwiftBar plugin reads that ledger for its "Codex this week" section.
#
# Token semantics (verified against ~/.codex usage records):
#   * input_tokens INCLUDES cached_input_tokens, so billable input = input - cached.
#   * reasoning_output_tokens is a SUBSET of output_tokens (never billed twice).
#   * codex-cli >= 0.145 v2 stream: `turn.completed.usage` is PER TURN, so the
#     values are SUMMED across turns. A single-prompt `codex exec` normally emits
#     exactly one turn; when more than one is seen the wrapper prints a note to
#     stderr, because per-turn semantics have only been observed for single-turn
#     runs and a thread-cumulative field would be double-counted by summing.
#   * legacy rollout schema: `info.total_token_usage` is CUMULATIVE, so only the
#     LAST event is taken. That is why the two branches differ.
#   * cache_write_input_tokens exists in the v2 stream but is deliberately NOT
#     logged — the ledger schema is fixed. Known small under-count.
#
# The captured JSONL stream is NEVER echoed: `item.completed` records carry the
# model's own answer text, and this wrapper runs inside the codex-proxy agent,
# which must never take task payload into its context. On failure it prints only
# an events-file path and the sequence of event types.
#
# Logging never fails a run: log_usage is called as `log_usage || true` and every
# internal problem goes to stderr with a `codex-exec-logged:` prefix.

set -euo pipefail

# Real directory of this script, through any chain of symlinks (plugin cache,
# a symlink in a bin dir). Agents live at <real dir>/../agents.
src="${BASH_SOURCE[0]}"
while [[ -L "$src" ]]; do
  link_dir="$(cd -P "$(dirname "$src")" && pwd)"
  src="$(readlink "$src")"
  case "$src" in /*) ;; *) src="$link_dir/$src" ;; esac
done
self_dir="$(cd -P "$(dirname "$src")" && pwd)"
self="$self_dir/$(basename "$src")"

# Wrapper options, any order, before the codex args.
# --detach <done-file>: run codex in the background. The parent writes only the
# caller's prompt into a temp file and re-executes this script with nohup in
# foreground mode; that child composes the context in memory, runs codex, and
# touches <done-file> (content = codex exit code). The parent returns at once
# with the PID on stdout. The caller polls for the done-file; it never re-runs
# codex for a job that has no done-file yet.
detach_done=""
role=""
prompt_file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --detach)      detach_done="${2:?--detach needs a done-file path}"; shift 2 ;;
    --role)        role="${2:?--role needs a name}"; shift 2 ;;
    --prompt-file) prompt_file="${2:?--prompt-file needs a path}"; shift 2 ;;
    *) break ;;
  esac
done

# Detached child: role and resolved codex cwd arrive via env from the parent.
ctx_cwd=""
if [[ -n "${CODEX_CTX_CWD:-}" ]]; then
  ctx_cwd="$CODEX_CTX_CWD"
  role="${CODEX_ROLE:-}"
  unset CODEX_CTX_CWD CODEX_ROLE
fi

if [[ -n "$prompt_file" ]]; then
  if [[ ! -f "$prompt_file" ]]; then
    echo "codex-exec-logged: prompt file not found: $prompt_file" >&2
    exit 3
  fi
fi
last_arg=""
[[ $# -gt 0 ]] && last_arg="${!#}"
if [[ -n "$prompt_file" && "$last_arg" != "-" ]]; then
  set -- "$@" -
  last_arg="-"
fi
compose=0
[[ "$last_arg" == "-" ]] && compose=1
if [[ -n "$role" && "$compose" != 1 ]]; then
  echo "codex-exec-logged: --role needs - or --prompt-file" >&2
  exit 2
fi

# Role file: name must match ^[a-z][a-z-]*$ and exist in the sibling agents dir.
role_file=""
if [[ -n "$role" ]]; then
  if [[ ! "$role" =~ ^[a-z][a-z-]*$ ]]; then
    echo "codex-exec-logged: unknown role $role" >&2
    exit 2
  fi
  agents_dir="$self_dir/../agents"
  if [[ ! -d "$agents_dir" ]]; then
    echo "codex-exec-logged: agents dir not found: $agents_dir" >&2
    exit 2
  fi
  role_file="$agents_dir/$role.md"
  if [[ ! -f "$role_file" ]]; then
    echo "codex-exec-logged: unknown role $role" >&2
    exit 2
  fi
fi

# Scan the argv for ledger metadata and the codex cwd without consuming it.
model=""
effort=""
cd_arg=""
prev=""
unquote() {
  local v="$1"
  v="${v%\"}"; v="${v#\"}"
  v="${v%\'}"; v="${v#\'}"
  printf '%s' "$v"
}
for arg in "$@"; do
  # Both the space-separated form (-m V) and the glued form (--model=V) are
  # recognised: an unlogged model would silently fall back to the most expensive
  # tier in the plugin's price table.
  case "$arg" in
    --model=*) model="$(unquote "${arg#--model=}")" ;;
    -m=*)      model="$(unquote "${arg#-m=}")" ;;
    model_reasoning_effort=*) effort="$(unquote "${arg#model_reasoning_effort=}")" ;;
    --cd=*)    cd_arg="${arg#--cd=}" ;;
  esac
  case "$prev" in
    -m|--model) model="$(unquote "$arg")" ;;
    -C|--cd)    cd_arg="$arg" ;;
  esac
  prev="$arg"
done

# codex cwd, logical path (cd resolves a relative value against $PWD).
if [[ -z "$ctx_cwd" && "$compose" == 1 ]]; then
  if [[ -n "$cd_arg" ]]; then
    ctx_cwd="$(cd "$cd_arg" 2>/dev/null && pwd)" || ctx_cwd=""
  else
    ctx_cwd="$PWD"
  fi
fi

style="${CODEX_STYLE_FILE:-$self_dir/codex-style.md}"

# section <header> <file>: header line plus file content, only for a non-empty file.
section() {
  if [[ -s "$2" ]]; then
    printf '[%s]\n%s\n\n' "$1" "$(cat "$2")"
  fi
}
# Agent body: drop a leading `---` frontmatter block and the single separator
# newline after it.
role_body() {
  awk 'NR == 1 && $0 == "---" { fm = 1; next }
       fm == 1 { if ($0 == "---") { fm = 2; sep = 1 } ; next }
       sep == 1 { sep = 0; if ($0 == "") next }
       { print }' "$1"
}
compose_stdin() {
  if [[ "$compose" != 1 ]]; then
    cat
    return 0
  fi
  if [[ -n "$role" ]]; then
    printf '[ROLE: %s]\n%s\n\n' "$role" "$(role_body "$role_file")"
  fi
  section "USER CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  if [[ -n "$ctx_cwd" ]]; then
    section "PROJECT CLAUDE.md" "$ctx_cwd/CLAUDE.md"
    section "MEMORY INDEX" "$HOME/.claude/projects/$(printf '%s' "$ctx_cwd" | tr '/.' '--')/memory/MEMORY.md"
  fi
  section "RESPONSE STYLE" "$style"
  printf '[TASK]\n'
  if [[ -n "$prompt_file" ]]; then
    cat "$prompt_file"
  else
    cat
  fi
}

if [[ "${CODEX_EXEC_DRY_RUN:-0}" == 1 ]]; then
  compose_stdin
  echo
  printf 'CODEX ARGV: exec --json'
  for arg in "$@"; do printf ' %q' "$arg"; done
  printf '\n'
  exit 0
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "codex-exec-logged: codex not found" >&2
  exit 127
fi

if [[ -n "$detach_done" ]]; then
  # The parent never composes: the temp file holds the caller's prompt only.
  # The child opens it, unlinks it at once, and composes in memory.
  rm -f "$detach_done"
  stdin_file="$(mktemp "${TMPDIR:-/tmp}/codex-stdin.XXXXXX")"
  if [[ -n "$prompt_file" ]]; then
    cat "$prompt_file" >"$stdin_file"
  else
    cat >"$stdin_file"
  fi
  detach_log="${detach_done}.log"
  CODEX_ROLE="$role" CODEX_CTX_CWD="${ctx_cwd:-$PWD}" CODEX_STYLE_FILE="$style" \
  nohup bash -c '
    done_file="$1"; stdin_file="$2"; wrapper="$3"; shift 3
    rc=0
    exec 3<"$stdin_file"
    rm -f "$stdin_file"
    "$wrapper" "$@" <&3 || rc=$?
    exec 3<&-
    printf "%s\n" "$rc" >"$done_file"
  ' _ "$detach_done" "$stdin_file" "$self" "$@" >"$detach_log" 2>&1 &
  echo "$!"
  exit 0
fi

# mktemp template: the X's must be LAST — BSD mktemp does not substitute a
# "...XXXXXX.jsonl" template, which would make parallel runs share one file.
events="$(mktemp "${TMPDIR:-/tmp}/codex-events.XXXXXX")"
trap 'rm -f "$events"' EXIT

# Failure diagnostics from earlier runs are kept on purpose (see the rc != 0 path
# below), but they hold the full JSONL stream and must not accumulate forever.
# Prune anything older than a day; TMPDIR cleanup is otherwise the only reaper.
find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'codex-events-failed.*.jsonl' -mtime +1 -delete 2>/dev/null || true

log_usage() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "codex-exec-logged: jq not found, usage not logged" >&2
    return 0
  fi

  local usage schema line ts
  # v2 stream: sum every turn.completed usage (per-turn semantics).
  # -R -s + `fromjson?` instead of plain -s: slurp mode is all-or-nothing, so a
  # single non-JSON line on codex's stdout (a banner, a progress line from a
  # future codex-cli) would drop the whole run's usage. Bad lines are skipped.
  usage="$(jq -R -s -c '
      [ split("\n")[] | select(length > 0) | fromjson? | select(type == "object") ] as $ev
      | [ $ev[] | select(.type=="turn.completed" and .usage != null) | .usage ] as $u
      | if ($u|length) == 0 then empty
        else { turns: ($u|length),
               input:            ($u | map(.input_tokens            // 0) | add),
               cached_input:     ($u | map(.cached_input_tokens     // 0) | add),
               output:           ($u | map(.output_tokens           // 0) | add),
               reasoning_output: ($u | map(.reasoning_output_tokens // 0) | add) }
        end' "$events" 2>/dev/null || true)"
  schema=v2
  if [[ -z "$usage" ]]; then
    # legacy rollout schema: info.total_token_usage is CUMULATIVE -> take the LAST event.
    usage="$(jq -R -s -c '
        [ split("\n")[] | select(length > 0) | fromjson? | select(type == "object") ] as $ev
        | [ $ev[] | select(.type=="event_msg" and .payload.type=="token_count"
                       and .payload.info != null) | .payload.info.total_token_usage ] as $u
        | if ($u|length) == 0 then empty
          else ($u[-1]) | { turns: 1,
                 input:            (.input_tokens            // 0),
                 cached_input:     (.cached_input_tokens     // 0),
                 output:           (.output_tokens           // 0),
                 reasoning_output: (.reasoning_output_tokens // 0) }
          end' "$events" 2>/dev/null || true)"
    schema=legacy
  fi
  if [[ -z "$usage" ]]; then
    echo "codex-exec-logged: no usage events found, usage not logged" >&2
    return 0
  fi

  if [[ "$schema" == "v2" ]]; then
    local turns
    turns="$(jq -r '.turns // 1' <<<"$usage" 2>/dev/null || echo 1)"
    if [[ "$turns" != "1" ]]; then
      echo "codex-exec-logged: $turns turn.completed events, usage summed" >&2
    fi
  fi

  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  line="$(jq -c -n --arg ts "$ts" --arg model "$model" --arg effort "$effort" \
            --arg label "${CODEX_LABEL:-}" --argjson u "$usage" \
            '{ts:$ts, model:$model, effort:$effort,
              input:$u.input, cached_input:$u.cached_input,
              output:$u.output, reasoning_output:$u.reasoning_output,
              label:$label}')"
  if [[ -z "$line" ]]; then
    echo "codex-exec-logged: could not compose ledger line, usage not logged" >&2
    return 0
  fi

  mkdir -p "$HOME/.codex"
  # One printf = one write() in O_APPEND mode, atomic for concurrent runs.
  printf '%s\n' "$line" >> "$HOME/.codex/proxy-usage.jsonl"
}

rc=0
# stderr is intentionally NOT redirected: the caller's error contract reads it.
compose_stdin | codex exec --json "$@" >"$events" || rc=$?

if [[ "$rc" != 0 ]]; then
  # Keep the evidence: the EXIT trap deletes $events.
  keep="${TMPDIR:-/tmp}/codex-events-failed.$$.jsonl"
  cp "$events" "$keep" 2>/dev/null || true
  echo "codex-exec-logged: codex exit rc=$rc, events kept at $keep" >&2
  if command -v jq >/dev/null 2>&1; then
    # Event TYPES only — never .item.text, which is model-generated answer text.
    echo "codex-exec-logged: event types: $(jq -r 'select(.type != null) | .type' "$keep" 2>/dev/null | tail -n 20 | tr '\n' ' ')" >&2
    # `(.type? // "")` first: `null|test(...)` raises, and `//` does not catch errors.
    jq -c 'select(((.type? // "")|test("error|failed"))) | {type, error: (.error // .message // null)}' "$keep" 2>/dev/null | tail -n 5 >&2 || true
  fi
fi

log_usage || true

exit "$rc"
