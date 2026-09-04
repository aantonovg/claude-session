# Session map (subscription account)

Read by the `session:team` and `session:team-forks` skills. Row = task class, column =
role; a cell is `<model>-<effort>`. Teammates are spawned with the model alias and then
pinned to the full id below.

Default pairing: fable-opus. Main session default: fable-low.

| Class | Reviewer-debugger | Plan author/fixer | Code/test fixer | Code/test author | Fact researcher | Test/script executor |
|---|---|---|---|---|---|---|
| 1 very simple | opus-low | opus-low | opus-low | opus-low | opus-low | opus-low |
| 2 simple | opus-medium | opus-low | opus-low | opus-low | opus-low | opus-low |
| 3 medium | fable-low | opus-medium | opus-medium | opus-low | opus-low | opus-low |
| 4 complex | fable-medium | fable-low | opus-medium | opus-medium | opus-low | opus-low |
| 5 very complex | fable-high | fable-medium | opus-high | opus-medium | opus-low | opus-low |

Model ids:

| alias | full id |
|---|---|
| fable | `claude-fable-5-1[1m]` |
| opus | `claude-opus-5[1m]` |
| sonnet | `claude-sonnet-5[1m]` |
