# Intent form

The one form of the intent confirmation at `std` and `full`. The main session writes these lines
into `intent.md` and puts the same lines to the user in chat, in this order, and asks for the
confirmation in the same turn. Nothing but research is launched before the user's word.

```
Task: <what is wanted, one sentence, in the user's words>
Depth: <std | full>
Acceptance criteria:
1. <a quality criterion the result is checked against>
2. <...>
Open decisions: <each with the default taken first and what it rests on, or "none">
Review aspects: <the default list of the depth, below> (cut or extend)
```

The default list of the aspects line, cut by the depth; the user cuts it or extends it, and a
criterion that asks for an aspect of its own adds that aspect:

| depth | Review aspects |
|---|---|
| `std` | reliability, simplicity |
| `full` | reliability, simplicity, testability |

After the confirmation the aspects line of `intent.md` is rewritten to hold exactly the aspects
the user approved, and nothing else: a refused aspect leaves the line, an aspect the user added
joins it. The review stage takes its aspects from that line alone, never from the conversation.
