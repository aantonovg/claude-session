# Session map

Read by the `session:forks` and `session:pipeline` skills (and the unstable pool skills). One table per pairing
(`<reviewer family>-<executor family>`); row = task class 1-5, column = role; a cell is
`<model>-<effort>`. The skill uses the default pairing unless the user names another
one at invocation. Teammates are spawned with the model alias and then pinned to the
full id below.

Default pairing: fable-opus. Main session default: fable-low.

| alias | full id | efforts |
|---|---|---|
| fable | `claude-fable-5-1[1m]` | low, medium, high |
| opus | `claude-opus-5[1m]` | low, medium, high |
| sonnet | `claude-sonnet-5[1m]` | low, medium |

## fable-fable

| Class | Reviewer-debugger | Plan author/fixer | Code/test fixer | Code/test author | Fact researcher | Test/script executor |
|---|---|---|---|---|---|---|
| 1 very simple | opus-low | opus-low | opus-low | opus-low | opus-low | opus-low |
| 2 simple | opus-medium | opus-low | opus-low | opus-low | opus-low | opus-low |
| 3 medium | fable-low | opus-medium | fable-low | opus-low | opus-low | opus-low |
| 4 complex | fable-medium | fable-low | fable-low | opus-medium | opus-low | opus-low |
| 5 very complex | fable-high | fable-medium | fable-medium | fable-low | opus-low | opus-low |

## fable-opus

| Class | Reviewer-debugger | Plan author/fixer | Code/test fixer | Code/test author | Fact researcher | Test/script executor |
|---|---|---|---|---|---|---|
| 1 very simple | opus-low | opus-low | opus-low | opus-low | opus-low | opus-low |
| 2 simple | opus-medium | opus-low | opus-low | opus-low | opus-low | opus-low |
| 3 medium | fable-low | opus-medium | opus-medium | opus-low | opus-low | opus-low |
| 4 complex | fable-medium | fable-low | opus-medium | opus-medium | opus-low | opus-low |
| 5 very complex | fable-high | fable-medium | opus-high | opus-medium | opus-low | opus-low |

## opus-opus

| Class | Reviewer-debugger | Plan author/fixer | Code/test fixer | Code/test author | Fact researcher | Test/script executor |
|---|---|---|---|---|---|---|
| 1 very simple | opus-low | opus-low | opus-low | opus-low | opus-low | opus-low |
| 2 simple | opus-medium | opus-low | opus-low | opus-low | opus-low | opus-low |
| 3 medium | opus-medium | opus-medium | opus-medium | opus-low | opus-low | opus-low |
| 4 complex | opus-high | opus-medium | opus-medium | opus-medium | opus-low | opus-low |
| 5 very complex | opus-high | opus-high | opus-high | opus-medium | opus-low | opus-low |
