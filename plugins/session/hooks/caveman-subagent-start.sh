#!/bin/sh
# SubagentStart hook: hands every subagent (fork, waiter, workflow agent) the caveman
# ruleset at the level the main session runs, so cold agents answer as tersely as the
# main session. The caveman plugin itself hooks only SessionStart and UserPromptSubmit,
# which never reach a subagent.
#
# Level: ~/.claude/.caveman-active (written by the caveman plugin), default ultra.
# Text: the caveman skill's SKILL.md from the plugin cache when present, else a
# built-in fallback. Output: one hookSpecificOutput JSON with additionalContext.
CLAUDE_DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
LEVEL=$(head -c 40 "$CLAUDE_DIR/.caveman-active" 2>/dev/null | tr -d '[:space:]')
case "$LEVEL" in lite|full|ultra|wenyan-lite|wenyan-full|wenyan-ultra) ;; off) exit 0 ;; *) LEVEL=ultra ;; esac
SKILL=""
for f in "$CLAUDE_DIR"/plugins/cache/caveman/caveman/*/skills/caveman/SKILL.md; do [ -f "$f" ] && SKILL=$f; done
TMP=$(mktemp "${TMPDIR:-/tmp}/caveman-sub.XXXXXX")
{
  printf 'CAVEMAN MODE ACTIVE — level: %s\n\n' "$LEVEL"
  if [ -n "$SKILL" ]; then
    awk 'BEGIN{fm=0} NR==1 && /^---$/ {fm=1; next} fm==1 && /^---$/ {fm=2; next} fm!=1 {print}' "$SKILL"
  else
    cat <<'FALLBACK'
Rules: drop articles (a/an/the), filler (just/really/basically), pleasantries, hedging. Fragments OK.
Short synonyms (big not extensive, fix not "implement a solution for"). No tool-call narration.
No decorative tables or emoji. No long raw logs; quote shortest decisive line.
Standard tech acronyms OK (DB/API/HTTP); never invent abbreviations (cfg/impl/req/fn).
No arrows (X → Y). Technical terms exact. Code blocks unchanged. Errors quoted exact.
Never drop not/never/no/only/except. Numbers and units exact.
Never add words to sound caveman; compression only. Keep correct verb forms when same length.
Ultra: strip conjunctions when cause-then-effect stays clear; one word when one word enough; each fact once.
Drop caveman for security warnings, irreversible-action confirmations and multi-step sequences where order matters.
Persisted output stays normal prose: code, comments, commits, docs, tickets, MR threads, memory files, messages to other people.
Reply in the language the user writes; compress the style, not the language.
Pattern: [thing] [action] [reason]. [next step].
FALLBACK
  fi
} > "$TMP"
python3 - "$TMP" <<'PY'
import json, sys
text = open(sys.argv[1], encoding='utf-8').read()
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SubagentStart", "additionalContext": text}}))
PY
rm -f "$TMP"
exit 0
