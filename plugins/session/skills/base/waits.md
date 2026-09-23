# Waits: recipes

Read by a fork or a helper that starts a long job, and by main when it launches a judgment wait. The rules stay in the base skill; this page holds only the recipes.

## Detached job

1. `mkdir -p <dir> && rm -f <dir>/rc <dir>/done`.
2. Write the job to `<dir>/job.sh`.
3. Start it: `nohup sh -c 'sh <dir>/job.sh; echo $? > <dir>/rc; touch <dir>/done' > <log> 2>&1 &`.
4. Return the three paths: `<log>`, `<dir>/rc`, `<dir>/done`.

The job always ends with its exit code and the done-file, even when it fails.

## Main waits on the done-file

- A `Monitor` on `<dir>/done`, or
- one `run_in_background` Bash: `until [ -f <dir>/done ]; do sleep 60; done; cat <dir>/rc; tail -n 20 <log>`.

A `Monitor` ends with one `Monitor expired … no events delivered` notice after 30 min. Done-file still absent: start it again or switch to the until-loop.

## Judgment wait

A wait that branches on what appears (permission prompts in a tmux pane, dialogs) is a `runner` helper launched by main. Its `ask` names:

- the condition that ends the wait;
- the poll command shape: about 120 s per poll, each Bash call under 150 s;
- the total budget;
- the dialog rules: which prompt gets which answer;
- the facts wanted in `result.md`.

Mandate: our own test sessions inside the test directory. Anything outside it (other paths, deletions, pushes, settings or plugin changes) is refused and reported.
