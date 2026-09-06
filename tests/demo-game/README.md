# Demo game benchmark kit

Compares session modes on one identical task: build the "Asteroid Dodge" browser game
described in `prompt.md`. Every run gets the same prompt, the same plugin version and a
fresh git repository; only the mode, model and effort differ.

## Planned runs

| run name | mode | model | effort | note |
|---|---|---|---|---|
| pipeline-opus | `pipeline` | `claude-opus-5[1m]` | low | class as proposed by the session |
| pipeline-fable | `pipeline` | `claude-fable-5-1[1m]` | low | same |
| workflow-fable-opus | `workflow` | `claude-fable-5-1[1m]` | low | old workflow flow, fable-opus pairing |
| pipeline-fast-opus | `pipeline fast` | `claude-opus-5[1m]` | low | economy mode 1 |
| pipeline-standard-opus | `pipeline standard` | `claude-opus-5[1m]` | low | economy mode 2 |

## Use

- Launch: `./launch.sh <run-name> <mode> <model-id> <effort>` creates
  `~/projects/demo-game-runs/<run-name>/`, starts tmux session `demo-<run-name>`, sends the
  mode skill and the task line. Watch with `tmux attach -t demo-<run-name>`.
- Score: `./score.sh ~/projects/demo-game-runs/<run-name>` prints tests passed/failed,
  commits, source files, JS lines, index/README presence, `node --check` result and the
  session JSONL path.
- Cost: pipeline runs `python3 ../../tools/pipeline-cost.py <task dir>` (task dir under
  `~/.claude/projects/<encoded run dir>/pipeline/`); other runs sum the usage fields of
  the session JSONL printed by `score.sh`.
