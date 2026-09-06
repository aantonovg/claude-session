#!/usr/bin/env bash
# codex-exec-logged.sh — a thin logging wrapper around `codex exec`.
#
# Drop-in for `codex exec`: it forwards every argument verbatim and only adds
# `--json`, so the caller's flags (-m, -c, -s, -C, -o, --ephemeral, the trailing
# `-` with stdin redirection) keep working unchanged. codex's exit code is the
# wrapper's exit code, and the answer still lands only in the `-o` file.
#
# Side effect: one JSON line per run is appended to ~/.codex/proxy-usage.jsonl
#   {"ts","model","effort","input","cached_input","output","reasoning_output"}
# The claude-cost SwiftBar plugin reads that ledger for its "Codex this week"
# section.
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

# --detach <done-file>: run codex in the background. The wrapper composes the
# stdin (style block + prompt) into a temp file, re-executes itself with nohup
# in foreground mode reading that file, and returns at once with the PID on
# stdout. The background run writes the -o answer file and the ledger row as
# usual, then touches <done-file> (its content is the codex exit code). The
# caller polls for the done-file; it never re-runs codex for a job that has no
# done-file yet.
detach_done=""
if [[ "${1:-}" == "--detach" ]]; then
  detach_done="${2:?--detach needs a done-file path}"
  shift 2
fi

# mktemp template: the X's must be LAST — BSD mktemp does not substitute a
# "...XXXXXX.jsonl" template, which would make parallel runs share one file.
events="$(mktemp "${TMPDIR:-/tmp}/codex-events.XXXXXX")"
trap 'rm -f "$events"' EXIT

# Failure diagnostics from earlier runs are kept on purpose (see the rc != 0 path
# below), but they hold the full JSONL stream and must not accumulate forever.
# Prune anything older than a day; TMPDIR cleanup is otherwise the only reaper.
find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'codex-events-failed.*.jsonl' -mtime +1 -delete 2>/dev/null || true

# Scan the argv for ledger metadata without consuming it.
model=""
effort=""
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
  esac
  case "$prev" in
    -m|--model)
      model="$(unquote "$arg")"
      ;;
  esac
  prev="$arg"
done

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
            --argjson u "$usage" \
            '{ts:$ts, model:$model, effort:$effort,
              input:$u.input, cached_input:$u.cached_input,
              output:$u.output, reasoning_output:$u.reasoning_output}')"
  if [[ -z "$line" ]]; then
    echo "codex-exec-logged: could not compose ledger line, usage not logged" >&2
    return 0
  fi

  mkdir -p "$HOME/.codex"
  # One printf = one write() in O_APPEND mode, atomic for concurrent runs.
  printf '%s\n' "$line" >> "$HOME/.codex/proxy-usage.jsonl"
}

rc=0
# Style block: when the prompt comes on stdin (trailing `-`) and the style file
# exists next to this wrapper, it is prepended to the prompt so every codex run
# gets the same response-style rules as the Claude agents. The prompt text never
# passes through the calling agent: the concatenation happens here, in the shell.
# CODEX_STYLE_FILE overrides the path; CODEX_EXEC_DRY_RUN=1 prints the composed
# stdin and exits without running codex (test hook).
style="${CODEX_STYLE_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/codex-style.md}"
last_arg=""
[[ $# -gt 0 ]] && last_arg="${!#}"
if [[ "$last_arg" == "-" && -f "$style" ]]; then
  compose_stdin() { cat "$style"; echo; cat; }
else
  compose_stdin() { cat; }
fi
if [[ "${CODEX_EXEC_DRY_RUN:-0}" == 1 ]]; then
  compose_stdin
  exit 0
fi
if [[ -n "$detach_done" ]]; then
  # Compose once here (style + prompt), then hand the composed file to a
  # foreground child that runs codex; the child's stdin is that file, so the
  # style prepend must not run twice: the child sees no style file.
  rm -f "$detach_done"
  stdin_file="$(mktemp "${TMPDIR:-/tmp}/codex-stdin.XXXXXX")"
  compose_stdin >"$stdin_file"
  detach_log="${detach_done}.log"
  nohup bash -c '
    done_file="$1"; stdin_file="$2"; wrapper="$3"; shift 3
    rc=0
    CODEX_STYLE_FILE=/nonexistent "$wrapper" "$@" <"$stdin_file" || rc=$?
    rm -f "$stdin_file"
    printf "%s\n" "$rc" >"$done_file"
  ' _ "$detach_done" "$stdin_file" "${BASH_SOURCE[0]}" "$@" >"$detach_log" 2>&1 &
  echo "$!"
  exit 0
fi
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
