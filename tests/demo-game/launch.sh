#!/usr/bin/env zsh
# Launch one benchmark run of the demo game task in a tmux-driven Claude Code session.
# Usage: launch.sh <run-name> <mode> <model-id> <effort> [extra-skill-line]
#   mode    : session mode skill line, e.g. 'pipeline full' | 'none' (base only, no skill)
#   model-id: e.g. claude-opus-5[1m] | claude-fable-5-1[1m]
#   effort  : low | medium | high
#   extra   : optional second skill sent as /session:<extra> after the mode, e.g. 'codex sol'
set -euo pipefail

if [[ $# -lt 4 || $# -gt 5 ]]; then
  echo "usage: $0 <run-name> <mode> <model-id> <effort> [extra-skill-line]" >&2
  exit 2
fi
run_name=$1 mode=$2 model=$3 effort=$4 extra=${5:-}
kit_dir=${0:A:h}
runs_root=~/projects/demo-game-runs
run_dir=$runs_root/$run_name
tmux_name=demo-$run_name
plugin_dir=~/projects/claude-session/plugins/session
log=${TMPDIR:-/var/tmp}/demo-launch.log

if [[ -e $run_dir ]]; then
  echo "run dir already exists: $run_dir" >&2
  exit 1
fi
if tmux has-session -t "$tmux_name" 2>/dev/null; then
  echo "tmux session already exists: $tmux_name" >&2
  exit 1
fi

pane() { tmux capture-pane -p -t "$tmux_name" | grep -v '^[[:space:]]*$' | tail -20; }
alive() { [[ $(tmux display-message -p -t "$tmux_name" '#{pane_current_command}') != zsh ]]; }

# wait_for <regex> <timeout-s>: poll the pane; answers the trust dialog on the way.
# Returns 1 when claude is not running any more (exited with an error) or on timeout.
wait_for() {
  local re=$1 limit=$2 t=0 out
  while (( t < limit )); do
    out=$(pane)
    if grep -q 'Yes, I trust this folder' <<<"$out"; then
      tmux send-keys -t "$tmux_name" Down Enter
      sleep 3; t=$((t+3)); continue
    fi
    if grep -Eq "$re" <<<"$out"; then return 0; fi
    if (( t >= 15 )) && ! alive; then
      echo "$tmux_name: claude exited: $(tail -3 <<<"$out" | tr '\n' ' ')" | tee -a "$log" >&2
      return 1
    fi
    sleep 3; t=$((t+3))
  done
  echo "$tmux_name: timeout waiting for /$re/" | tee -a "$log" >&2
  return 1
}

mkdir -p "$run_dir"
cp "$kit_dir/prompt.md" "$run_dir/prompt.md"
git -C "$run_dir" init -q
git -C "$run_dir" add prompt.md
git -C "$run_dir" commit -q -m "Add task prompt"

# Start a plain shell first; the claude command goes in via send-keys.
# An inline command in `tmux new-session` exits at once ("no server running").
tmux new-session -d -s "$tmux_name" -c "$run_dir" -x 200 -y 50
tmux send-keys -t "$tmux_name" "claude --plugin-dir $plugin_dir --model '$model' --effort $effort" Enter
# ready = the input prompt line, after the trust dialog was answered
wait_for '^❯ |shift\+tab to cycle|\? for shortcuts' 90 || exit 1
sleep 2
# the base is a skill since 0.8.0: every run invokes it first
tmux send-keys -t "$tmux_name" "/session:base" Enter
wait_for 'Base on, ping cron' 120 || exit 1
if [[ $mode != none ]]; then
  tmux send-keys -t "$tmux_name" "/session:$mode" Enter
  wait_for 'mode on|Pipeline review' 90 || exit 1
fi
if [[ -n $extra ]]; then
  tmux send-keys -t "$tmux_name" "/session:$extra" Enter
  wait_for 'codex|Codex' 90 || exit 1
fi
sleep 2
tmux send-keys -t "$tmux_name" "Read prompt.md in this directory and do the task in full." Enter

echo "tmux session: $tmux_name"
echo "run dir:      $run_dir"
echo "attach:       tmux attach -t $tmux_name"
