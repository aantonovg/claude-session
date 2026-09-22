# Shared helpers of tests/plugin/*.sh: sourced, never run.
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
P=$REPO/plugins/session
N=0; FAILS=0
pass() { N=$((N + 1)); }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }
check() { local label=$1; shift; if "$@"; then pass; else fail "$label"; fi; }
done_with() {  # $1 suite name
  if [ "$FAILS" -eq 0 ]; then echo "$1: PASS $N"; exit 0; fi
  echo "$1: FAIL $FAILS failures, $N checks passed"; exit 1
}
# tokens(text): a word count times 1.3, the approximation the description limits use
tokens() { python3 -c 'import sys; print(int(len(sys.stdin.read().split()) * 1.3))'; }
frontmatter() { awk 'NR==1&&$0!="---"{exit} NR>1&&$0=="---"{exit} NR>1{print}' "$1"; }
body() { awk 'NR==1&&$0!="---"{p=1} p{print; next} NR>1&&$0=="---"{p=1}' "$1"; }
