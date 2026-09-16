#!/bin/sh
# Plain mode (no args): one line per named workflow, "- <launch name> — <usage text>".
#   Sources: plugin workflows (session:<stem>), $HOME/.claude/workflows and
#   ${CLAUDE_PROJECT_DIR:-$PWD}/.claude/workflows (<stem>); a project entry overrides a user entry.
# Hook mode: --hook (--file <wf.js> | --dir <path|@user|@project>) [--prefix <plugin>]
#   prints one SessionStart hook JSON whose additionalContext holds one entry per workflow:
#   "Workflow <prefix>:<stem> (launch by name; contract below; never read the script body): <usage>".
#   @user = $HOME/.claude/workflows minus stems present in the project dir;
#   @project = ${CLAUDE_PROJECT_DIR:-$PWD}/.claude/workflows, silent when it is the user or plugin dir.
# stdout only, always exit 0; nothing printed when there is no entry.

DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
TAB=$(printf '\t')

real() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s\n' "$1"; }

usage_of() {  # $1 file, $2 whitespace class collapsed to one space (default spaces, tabs, CR)
  awk -v ws="${2:-[ \t\r]+}" '
    !f && /\/\* usage:/ { f = 1; sub(/.*\/\* usage:/, "") }
    f {
      if (index($0, "*/")) { sub(/\*\/.*/, ""); t = t " " $0; done = 1; exit }
      t = t " " $0
    }
    END {
      if (!f) { print "(no usage block)"; exit }
      gsub(ws, " ", t); sub(/^ /, "", t); sub(/ $/, "", t)
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

PD="$DIR/../workflows"; UD="$HOME/.claude/workflows"; JD="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/workflows"

if [ $# -eq 0 ]; then
  {
    scan p 'session:' "$PD"
    RU=$(real "$UD"); RJ=$(real "$JD"); RP=$(real "$PD")
    scan u '' "$UD"
    if [ "$RJ" != "$RU" ] && [ "$RJ" != "$RP" ]; then scan j '' "$JD"; fi
  } 2>/dev/null | awk -F "$TAB" '
    { k[NR] = $1; n[NR] = $2; l[NR] = substr($0, length($1) + length($2) + 3); if ($1 == "j") pj[$2] = 1 }
    END { for (i = 1; i <= NR; i++) if (!(k[i] == "u" && (n[i] in pj))) print l[i] }' 2>/dev/null
  exit 0
fi

HOOK=; FILE=; WDIR=; PREFIX=
while [ $# -gt 0 ]; do
  case $1 in
    --hook) HOOK=1 ;;
    --file|--dir|--prefix)
      [ $# -ge 2 ] || exit 0
      case $1 in --file) FILE=$2 ;; --dir) WDIR=$2 ;; --prefix) PREFIX=$2 ;; esac
      shift ;;
  esac
  shift
done
[ -n "$HOOK" ] || exit 0

entry() {  # $1 file
  s=$(basename "$1" .js)
  n=$s; [ -n "$PREFIX" ] && n="$PREFIX:$s"
  printf 'Workflow %s (launch by name; contract below; never read the script body): %s\n' "$n" "$(usage_of "$1" '[ \r]+')"
}

{
  if [ -n "$FILE" ]; then
    [ -f "$FILE" ] && entry "$FILE"
  elif [ -n "$WDIR" ]; then
    SKIP=
    case $WDIR in @user|@project) RJ=$(real "$JD") ;; esac
    case $WDIR in
      @user) D=$UD
        if [ "$RJ" != "$(real "$UD")" ] && [ "$RJ" != "$(real "$PD")" ]; then SKIP=$JD; fi ;;
      @project) D=$JD
        { [ "$RJ" = "$(real "$UD")" ] || [ "$RJ" = "$(real "$PD")" ]; } && exit 0 ;;
      *) D=$WDIR ;;
    esac
    if [ -d "$D" ]; then
      for f in "$D"/*.js; do
        [ -f "$f" ] || continue
        [ -n "$SKIP" ] && [ -f "$SKIP/$(basename "$f")" ] && continue
        entry "$f"
      done
    fi
  fi
} 2>/dev/null | LC_ALL=C awk '
  BEGIN {
    for (i = 1; i < 32; i++) m[sprintf("%c", i)] = sprintf("\\u%04x", i)
    m["\t"] = "\\t"; m["\\"] = "\\\\"; m["\""] = "\\\""
  }
  {
    o = ""; L = length($0)
    for (i = 1; i <= L; i++) { c = substr($0, i, 1); o = o ((c in m) ? m[c] : c) }
    t = (NR > 1) ? t "\\n" o : o
  }
  END { if (NR) printf "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"%s\"}}\n", t }' 2>/dev/null

exit 0
