#!/usr/bin/env zsh
# Launch one corporate pipeline test in a tmux-driven Claude Code session (bw harness).
# Usage: launch.sh <run-name> <jira-key> [model-id] [effort] [--no-prompt]
#   run-name : tmux session becomes corp-<run-name>
#   jira-key : e.g. B2CT-22401; the task prompt is tests/corp/prompt-<key>.md
#   model-id : default claude-fable-5-1[1m]
#   effort   : default low
#   --no-prompt : stop after the three mode skills (smoke test)
# Mode chain: /session:base -> /session:pipeline full -> /session:codex +astra -> task prompt.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <run-name> <jira-key> [model-id] [effort] [--no-prompt]" >&2
  exit 2
fi
run_name=$1 key=$2
model=${3:-'claude-fable-5-1[1m]'} effort=${4:-low}
no_prompt=0; [[ ${5:-} == --no-prompt || ${3:-} == --no-prompt || ${4:-} == --no-prompt ]] && no_prompt=1
[[ $model == --no-prompt ]] && model='claude-fable-5-1[1m]'
[[ $effort == --no-prompt ]] && effort=low
kit_dir=${0:A:h}
tmux_name=corp-$run_name
workspace=/Users/Shared/projects/b2connect-workspace
harness=/Users/aleksandr.antonov/projects/b2connect
prompt_file=$kit_dir/prompt-$key.md
log=${TMPDIR:-/var/tmp}/corp-launch.log

[[ -f $prompt_file ]] || { echo "missing prompt file: $prompt_file" >&2; exit 1; }
if tmux has-session -t "$tmux_name" 2>/dev/null; then
  echo "tmux session already exists: $tmux_name" >&2
  exit 1
fi

pane() { tmux capture-pane -p -t "$tmux_name" | grep -v '^[[:space:]]*$' | tail -20; }
alive() { [[ $(tmux display-message -p -t "$tmux_name" '#{pane_current_command}') != zsh ]]; }

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

# Same command as the user's `bw` shell function, plus model and effort.
claude_cmd="claude --add-dir $harness --settings $harness/.claude/settings.json --mcp-config $harness/.mcp.json --plugin-dir $harness/plugin --model '$model' --effort $effort"

tmux new-session -d -s "$tmux_name" -c "$workspace" -x 200 -y 50
tmux send-keys -t "$tmux_name" "zsh -lic \"$claude_cmd\"" Enter
wait_for '^❯ |shift\+tab to cycle|\? for shortcuts' 120 || exit 1
sleep 2
tmux send-keys -t "$tmux_name" "/session:base" Enter
wait_for 'Base on' 150 || exit 1
tmux send-keys -t "$tmux_name" "/session:pipeline full" Enter
wait_for 'ipeline' 120 || exit 1
tmux send-keys -t "$tmux_name" "/session:codex +astra" Enter
wait_for 'codex|Codex' 120 || exit 1
sleep 2
if (( no_prompt )); then
  echo "stopped before the task prompt (--no-prompt)"
else
  # one line: tmux send-keys with embedded newlines would submit early
  prompt=$(tr '\n' ' ' < "$prompt_file" | sed 's/  */ /g')
  tmux send-keys -t "$tmux_name" -l -- "$prompt"
  tmux send-keys -t "$tmux_name" Enter
fi

echo "tmux session: $tmux_name"
echo "attach:       tmux attach -t $tmux_name"
