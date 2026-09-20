#!/bin/bash
# Behavior runner of the 0.16 rebuild: one fresh tmux session per scenario, in a scratch project
# built by tests/rebuild/scenario-env.sh. Handed to .claude/workflows/test-session.js as `runner`.
#
#   tests/rebuild/scenario-run.sh [<key> ...]          run those scenario keys, or all of them
#   tests/rebuild/scenario-run.sh --verdict <key> <PASS|FAIL>   record the judge's verdict
#   tests/rebuild/scenario-run.sh --finished <jsonl> [<n>]      print how many workflow finish
#       notices the transcript holds, exit 0 once there are <n> (default 1). A notice is a
#       task-notification whose summary names a workflow and whose status is not still running;
#       the same notice is written twice (queued and delivered), so notices are counted by task id.
#
# Env: VARIANT (default base), SCENARIOS (default tests/measure/rebuild-scenarios-0.16.txt),
#      VERDICTS_ROOT (default $HOME/.claude/jobs/rebuild-0.16/results; outside the repo, like
#      tests/measure/basecls-run.sh, so a behavior run never dirties the worktree and never turns
#      the changed-path check of tests/workflows/usage-test.sh red; tests/rebuild/verdicts.sh
#      defaults to the same root), OUT (default <VERDICTS_ROOT>/<variant>/<run-ts>), IDLE_S (turn
#      idle cap, default 600), KEEP_PROJECT=1 (keep the scratch project after the run).
#
# Writes into OUT: result.log, commit, <key>.jsonl, <key>.pane.txt, verdicts.txt, done.
# verdicts.txt holds one line per scenario run:
#     <variant> <key> <PASS|FAIL> <run-ts> <commit>
# The driver writes FAIL for every key it ran, so a scenario nobody judged never reads as PASS;
# the judge of test-session records the real verdict afterwards with --verdict, and
# tests/rebuild/verdicts.sh takes the last line for the key. A key whose environment or setup never
# came up gets no verdict line at all — nothing was measured, so there is nothing to fail — and the
# run ends non-zero with that count instead.
#
# Scenario file format (free text, no id inside a test name):
#     <key>  base: <arguments or (none)>   prompts: "first prompt" "second prompt"
#         setup: <one shell line, run inside the scratch project>
#         finish: <prompt index> <how many workflow finish notices>
#         PASS: <the rule the judge applies>
#
# `finish` is the gate against a prompt racing a launch: that prompt is sent only after the
# transcript holds that many workflow finish notices, so a prompt that reads a result never runs
# while the workflow is still working. Without the field no prompt waits.
#
# Credential rule: real HOME, nothing read or copied from ~/.claude, ~/.claude.json or a keychain.
set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
HERE=$REPO/tests/rebuild
VARIANT=${VARIANT:-base}
SCENARIOS=${SCENARIOS:-$REPO/tests/measure/rebuild-scenarios-0.16.txt}
ROOT=${VERDICTS_ROOT:-$HOME/.claude/jobs/rebuild-0.16/results}
# The run directory names the run: when the caller hands OUT (the judge recording a verdict), the
# run-ts comes from its base name, never from a fresh date. Field 4 of a verdict line then always
# matches the directory it sits in.
if [ -n "${OUT:-}" ]; then
  RUN_TS=${RUN_TS:-$(basename "$OUT")}
else
  RUN_TS=${RUN_TS:-$(date +%Y%m%d-%H%M%S)}
  OUT=$ROOT/$VARIANT/$RUN_TS
fi
IDLE_S=${IDLE_S:-600}
R=$OUT/result.log
V=$OUT/verdicts.txt
C=$OUT/commit
export TERM=xterm-256color
log() { echo "[$(date +%H:%M:%S)] $*" >> "$R"; }

# notices <jsonl>: how many workflow finish notices the transcript holds, counted by task id. The
# session writes each notice twice (the queue operation and the delivered user message), and a
# background agent of the session writes notices of its own: only a summary naming a workflow
# counts, and only once its status left `running`.
notices() {
  python3 - "$1" <<'PY'
import json, re, sys
ids = set()
try:
    fh = open(sys.argv[1], encoding='utf-8', errors='replace')
except OSError:
    print(0); sys.exit(0)
for line in fh:
    try:
        d = json.loads(line)
    except Exception:
        continue
    s = json.dumps(d)
    if '<task-notification>' not in s:
        continue
    tid = re.search(r'<task-id>(.*?)</task-id>', s)
    summary = re.search(r'<summary>(.*?)</summary>', s)
    status = re.search(r'<status>(.*?)</status>', s)
    if not (tid and summary and status):
        continue
    if 'workflow' not in summary.group(1).lower():
        continue
    if status.group(1).strip().lower() in ('running', 'pending', 'queued'):
        continue
    ids.add(tid.group(1))
print(len(ids))
PY
}

if [ "${1:-}" = --finished ]; then
  f=${2:-}; want=${3:-1}
  [ -n "$f" ] || { echo "scenario-run: --finished wants a transcript path" >&2; exit 2; }
  [ -f "$f" ] || { echo "scenario-run: no transcript $f" >&2; exit 1; }
  n=$(notices "$f")
  echo "$n"
  [ "$n" -ge "$want" ] || exit 1
  exit 0
fi

if [ "${1:-}" = --verdict ]; then
  key=${2:-}; verdict=${3:-}
  case $verdict in PASS | FAIL) ;; *) echo "scenario-run: --verdict wants PASS or FAIL" >&2; exit 2 ;; esac
  [ -n "$key" ] || { echo "scenario-run: --verdict wants a key" >&2; exit 2; }
  # a verdict belongs to a run that happened: no fresh directory, no invented run-ts
  [ -d "$OUT" ] || { echo "scenario-run: --verdict wants the run directory in OUT, no such $OUT" >&2; exit 2; }
  # the commit of the verdict is the commit the run started at, recorded in the run directory,
  # never a fresh git rev-parse HEAD: HEAD moves between the run and the judgement, and the
  # ancestry guard of verdicts.sh only means something when the line names the commit that
  # produced the behavior.
  [ -f "$C" ] || { echo "scenario-run: --verdict wants the commit of the run in $C, no such file" >&2; exit 2; }
  COMMIT=$(cat "$C")
  [ -n "$COMMIT" ] || { echo "scenario-run: empty commit in $C" >&2; exit 2; }
  printf '%s %s %s %s %s\n' "$VARIANT" "$key" "$verdict" "$RUN_TS" "$COMMIT" >> "$V"
  echo "scenario-run: recorded $VARIANT $key $verdict in $V"
  exit 0
fi

mkdir -p "$OUT"
[ -f "$SCENARIOS" ] || { echo "scenario-run: no scenarios file $SCENARIOS" >&2; exit 2; }
# The commit under test, written once at the start of the run and read back by --verdict. A run
# started on an uncommitted tree describes no commit: HEAD does not name the code that ran, so the
# commit carries the marker `+dirty` and tests/rebuild/verdicts.sh refuses such a verdict. That is
# the only way a verdict of superseded code can be told from one of HEAD, since every run before a
# land step sits at the same HEAD.
COMMIT=$(git -C "$REPO" rev-parse HEAD)
[ -n "$(git -C "$REPO" status --porcelain -- plugins/session tests 2>/dev/null)" ] && COMMIT=$COMMIT+dirty
printf '%s\n' "$COMMIT" > "$C"

field() { # field <key> <name>: the value of "<name>:" inside the scenario block
  python3 - "$SCENARIOS" "$1" "$2" <<'PY'
import re, sys
path, key, name = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(path, encoding='utf-8').read().split('\n')
head = re.compile(r'^(\S+)\s')
block, on = [], False
for l in lines:
    m = head.match(l)
    if m and not l.startswith((' ', '\t', '#')):
        if on: break
        on = m.group(1) == key
    if on: block.append(l)
text = '\n'.join(block)
if name == 'prompts':
    # one NUL after every prompt, none joined: the reader loops over the whole stream
    tail = text.split('prompts:', 1)[1] if 'prompts:' in text else ''
    sys.stdout.write(''.join(p + '\x00' for p in re.findall(r'"((?:[^"\\]|\\.)*)"', tail)))
else:
    m = re.search(r'(?m)^\s*%s:\s*(.*)$' % re.escape(name), text)
    print(m.group(1).strip() if m else '')
PY
}

keys_all() { grep -E '^[A-Za-z][A-Za-z0-9_-]*[[:space:]].*prompts:' "$SCENARIOS" | awk '{print $1}'; }

KEYS=${*:-$(keys_all)}
[ -n "$KEYS" ] || { echo "scenario-run: no scenario key found in $SCENARIOS" >&2; exit 2; }

encode() { echo "$1" | sed 's#[/.]#-#g'; }
send() { tmux send-keys -t "$S" -l "$1"; sleep 1; tmux send-keys -t "$S" Enter; sleep 1; tmux send-keys -t "$S" Enter; }
newest() { ls -t "$PROJDIR"/*.jsonl 2>/dev/null | grep -vxF -f "$BEFORE" | head -1; }
wait_finished() { # wait until the live transcript holds <n> workflow finish notices, capped by IDLE_S
  local want=$1 f n
  for _ in $(seq 1 $((IDLE_S / 5))); do
    f=$(newest)
    if [ -n "$f" ]; then
      n=$(notices "$f")
      [ "$n" -ge "$want" ] && return 0
    fi
    sleep 5
  done
  return 1
}
wait_idle() { # a turn ends when the transcript stays untouched for 60 s, capped by IDLE_S
  local last=0 same=0 f m
  for _ in $(seq 1 $((IDLE_S / 5))); do
    sleep 5; f=$(newest)
    # no transcript yet is not idle: the session never started. The idle clock stays at 0 instead
    # of reading m=0 equal to last=0 and returning after 60 s.
    if [ -z "$f" ]; then same=0; last=0; continue; fi
    m=$(stat -f %m "$f" 2>/dev/null || echo 0)
    if [ "$m" = 0 ]; then same=0; last=0; continue; fi
    if [ "$m" = "$last" ]; then same=$((same + 5)); [ $same -ge 60 ] && return 0; else same=0; last=$m; fi
  done
  return 1
}

log "run $RUN_TS variant=$VARIANT commit=$COMMIT scenarios=$SCENARIOS keys=$(echo "$KEYS" | tr '\n' ' ')"

ERRORS=0
export REPO
for key in $KEYS; do
  PROJ=$OUT/project-$key
  # both, always: with --hide-old the plugin copy lives beside the project as <project>-plugin, so
  # clearing the project alone leaves a copy that makes scenario-env refuse a directory which is
  # not empty on the next run into the same OUT, and piles copies up under the results root
  rm -rf "$PROJ" "$PROJ-plugin"
  if ! bash "$HERE/scenario-env.sh" "$VARIANT" "$PROJ" >> "$R" 2>&1; then
    # an environment that never came up measured no behavior: that is an error of the run, never a
    # FAIL verdict of a scenario nobody ran
    log "$key: scenario-env failed, no verdict line written"
    echo "scenario-run: $key: scenario-env failed, see $R" >&2
    ERRORS=$((ERRORS + 1)); continue
  fi
  CARGS=$(cat "$PROJ/claude-args")
  setup=$(field "$key" setup)
  # the setup builds what the scenario measures (a baseline hash, a fixture tree): a setup that
  # failed is the same kind of environment error, and the scenario is not run at all
  if [ -n "$setup" ] && ! (cd "$PROJ" && eval "$setup") >> "$R" 2>&1; then
    log "$key: setup failed, no verdict line written"
    echo "scenario-run: $key: setup failed, see $R" >&2
    ERRORS=$((ERRORS + 1)); continue
  fi
  base=$(field "$key" base)
  PROJDIR=$HOME/.claude/projects/$(encode "$PROJ")
  mkdir -p "$PROJDIR"
  BEFORE=$OUT/$key.before
  ls "$PROJDIR"/*.jsonl > "$BEFORE" 2>/dev/null || : > "$BEFORE"
  S=sc-$VARIANT-$key
  tmux kill-session -t "$S" 2>/dev/null
  tmux new-session -d -x 200 -y 60 -s "$S" -c "$PROJ" "env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT claude $CARGS"
  sleep 10; tmux send-keys -t "$S" Down; sleep 1; tmux send-keys -t "$S" Enter; sleep 4
  case $base in '' | '(none)') send "/session:base" ;; *) send "/session:base $base" ;; esac
  wait_idle || log "$key: no reply to /session:base within $IDLE_S s"
  sleep 10
  # every prompt of the scenario, not only the first: one `read -d ''` per NUL-terminated record.
  # A single `read -r -d '' -a` stops at the first NUL and drops the rest silently.
  PROMPTS=()
  while IFS= read -r -d '' p; do PROMPTS+=("$p"); done < <(field "$key" prompts)
  # the gate of the `finish` field: the named prompt waits for the workflow finish notices, so a
  # prompt that reads a result never races the launch it reads
  FINISH=$(field "$key" finish)
  GIDX=$(awk '{print $1}' <<<"$FINISH")
  GWANT=$(awk '{print ($2 == "" ? 1 : $2)}' <<<"$FINISH")
  pi=0
  for p in ${PROMPTS[@]+"${PROMPTS[@]}"}; do
    [ -n "$p" ] || continue
    pi=$((pi + 1))
    if [ -n "$GIDX" ] && [ "$GIDX" = "$pi" ]; then
      if wait_finished "$GWANT"; then log "$key: prompt $pi gated on $GWANT workflow finish notice(s): seen"
      else log "$key: prompt $pi waited for $GWANT workflow finish notice(s), none within $IDLE_S s"; fi
    fi
    send "$p"
    wait_idle || log "$key: turn cap $IDLE_S s hit"
  done
  tmux capture-pane -p -S -200 -t "$S" > "$OUT/$key.pane.txt" 2>&1
  tmux send-keys -t "$S" Escape; sleep 1; tmux kill-session -t "$S" 2>/dev/null; sleep 2
  f=$(newest)
  if [ -n "$f" ]; then cp "$f" "$OUT/$key.jsonl"; log "$key: transcript $OUT/$key.jsonl"; else log "$key: no transcript"; fi
  rm -f "$BEFORE"
  [ "${KEEP_PROJECT:-0}" = 1 ] || rm -rf "$PROJ" "$PROJ-plugin"
  printf '%s %s FAIL %s %s\n' "$VARIANT" "$key" "$RUN_TS" "$COMMIT" >> "$V"
done

log "done ($ERRORS environment error(s))"
touch "$OUT/done"
echo "scenario-run: $OUT"
if [ "$ERRORS" -gt 0 ]; then
  echo "scenario-run: $ERRORS scenario(s) never ran: environment error, no verdict line for them" >&2
  exit 1
fi
