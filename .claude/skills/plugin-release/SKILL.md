---
name: plugin-release
description: "Use before ANY bump, reinstall, release or cache check of the session plugin: exact version files, split.sh, the uninstall+install@marketplace command, cache verification, commit message shape. Never recite the steps from memory."
---

# Releasing the session plugin

## 1. Find every place the version lives

The version string is duplicated. Two files hold it as data:

- `plugins/session/.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`

A third place is prose: the version log line at the top of the log section in `plugins/session/README.md`.

Do not edit these from memory. Read the current version out of `plugins/session/.claude-plugin/plugin.json`, then grep the repository for that exact string. Treat the grep output as the checklist and update every hit, adding a new README log line rather than rewriting the previous one. Re-run the same grep for the old version afterwards; a clean result is the signal that the bump is complete.

## 2. Regenerate the base skill

`plugins/session/skills/base/SKILL.md` is generated output. Never hand-edit it. Its source is `plugins/session/base/BASE.md`, and the generator is `plugins/session/base/split.sh`.

Confirm those paths with `ls` before you touch anything, because the base layout has moved between releases and a stale path silently writes nothing useful. Edit `BASE.md`, run `split.sh`, then diff the generated skill to confirm the change landed.

## 3. Respect the description budgets

Every description that ships in the plugin is loaded into context on every session, so each kind has a hard ceiling:

- skill descriptions: 100 tokens
- agent descriptions: 100 tokens
- workflow descriptions: 200 tokens, and every argument must carry its type

Check any description you touched during the release against its budget before committing. A bump is a good moment to sweep descriptions that have grown.

## 4. Reinstall

Uninstall and install as one command:

```
claude plugin uninstall session@claude-session && claude plugin install session@claude-session --scope user
```

Both halves matter. The marketplace suffix `@claude-session` is required: a bare `claude plugin install session` exits without an error and without installing anything, so a run that looks successful can leave the old version in place. The `--scope user` flag is required too, otherwise the install does not land where sessions read from.

## 5. Verify the cache

Confirm the install by listing the cache directory for the new version:

```
ls ~/.claude/plugins/cache/claude-session/session/<version>/
```

Substitute the version you just bumped to. If that directory is absent, the install did not happen, whatever the command printed. Do not proceed on the assumption that a quiet command succeeded.

## 6. Test from a fresh session

A session that was already running when you installed cannot resolve new workflow names. It resolved its workflow table at startup and will report an unknown name for anything the release added.

Two options: start a new session for the test, or, in the current session, launch the workflow by its `scriptPath` instead of its name. Use `scriptPath` when you want to test without losing the current context; otherwise a fresh session is the cleaner check, since it also exercises name resolution itself.

## 7. Commit

Commit messages follow one shape:

```
session <version>: <what changed>
```

The summary is lowercase, concrete, and describes the change rather than the act of releasing. Never add a Claude co-author line or any generated-with trailer to a commit in this repository.

Push only when the user asks. A finished bump, a verified install, and a local commit is the complete deliverable; leave the remote alone until you are told otherwise.

## Order of operations

1. Read the current version; grep for it.
2. Edit `BASE.md` if the release changes base rules; run `split.sh`.
3. Bump both JSON files; add the README log line.
4. Re-grep the old version; expect no hits.
5. Check description budgets.
6. Uninstall and install in one command.
7. `ls` the cache directory for the new version.
8. Test from a fresh session, or by `scriptPath`.
9. Commit. Stop.
