#!/bin/sh
# Prints one line per named workflow: "- <launch name> — <usage text>".
# Sources: plugin workflows (session:<stem>), $HOME/.claude/workflows and
# $PWD/.claude/workflows (<stem>); a project entry overrides a user entry.
# Injected into skills/base/SKILL.md: stdout only, always exit 0.

DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
TAB=$(printf '\t')

real() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s\n' "$1"; }

usage_of() {
  awk '
    !f && /\/\* usage:/ { f = 1; sub(/.*\/\* usage:/, "") }
    f {
      if (index($0, "*/")) { sub(/\*\/.*/, ""); t = t " " $0; done = 1; exit }
      t = t " " $0
    }
    END {
      if (!f) { print "(no usage block)"; exit }
      gsub(/[ \t\r]+/, " ", t); sub(/^ /, "", t); sub(/ $/, "", t)
      print t
    }' "$1" 2>/dev/null
}

scan() {  # $1 kind (p|u|j), $2 prefix, $3 dir
  [ -d "$3" ] || return 0
  for f in "$3"/*.js; do
    [ -f "$f" ] || continue
    s=$(basename "$f" .js)
    printf '%s\t%s\t- %s%s — %s\n' "$1" "$s" "$2" "$s" "$(usage_of "$f")"
  done 2>/dev/null
}

{
  PD="$DIR/../workflows"; UD="$HOME/.claude/workflows"; JD="$PWD/.claude/workflows"
  scan p 'session:' "$PD"
  RU=$(real "$UD"); RJ=$(real "$JD"); RP=$(real "$PD")
  scan u '' "$UD"
  if [ "$RJ" != "$RU" ] && [ "$RJ" != "$RP" ]; then scan j '' "$JD"; fi
} 2>/dev/null | awk -F "$TAB" '
  { k[NR] = $1; n[NR] = $2; l[NR] = substr($0, length($1) + length($2) + 3); if ($1 == "j") pj[$2] = 1 }
  END { for (i = 1; i <= NR; i++) if (!(k[i] == "u" && (n[i] in pj))) print l[i] }' 2>/dev/null

exit 0
