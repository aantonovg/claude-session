#!/bin/bash
# Install the pool daemon for the current user.
#   - symlinks pool/poolctl to ~/.local/bin/poolctl
#   - installs the LaunchAgent (macOS) or the systemd user unit (Linux)
#     with the repo path substituted, and starts it
#   - prints the daemon status
# Re-running is safe: the unit is replaced and restarted.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
UNITS="$REPO/pool/units"
mkdir -p "$HOME/.local/bin"
ln -sfn "$REPO/pool/poolctl" "$HOME/.local/bin/poolctl"
chmod +x "$REPO/pool/poolctl"
echo "poolctl -> $HOME/.local/bin/poolctl"

subst() { sed -e "s|@REPO@|$REPO|g" -e "s|@HOME@|$HOME|g" "$1"; }

case "$(uname -s)" in
  Darwin)
    LABEL=com.claude-session.poold
    PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
    mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
    subst "$UNITS/$LABEL.plist" > "$PLIST"
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
    launchctl kickstart -k "gui/$(id -u)/$LABEL"
    sleep 2
    launchctl print "gui/$(id -u)/$LABEL" | grep -E 'state|pid' | head -3
    ;;
  Linux)
    UNIT_DIR="$HOME/.config/systemd/user"
    mkdir -p "$UNIT_DIR"
    subst "$UNITS/poold.service" > "$UNIT_DIR/poold.service"
    systemctl --user daemon-reload
    systemctl --user enable --now poold.service
    systemctl --user restart poold.service
    sleep 2
    systemctl --user --no-pager status poold.service | head -5
    ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

sleep 1
if curl -sf "http://127.0.0.1:${POOLD_PORT:-19540}/status" >/dev/null; then
  echo "poold answers on port ${POOLD_PORT:-19540}"
else
  echo "poold not answering yet; check the log" >&2
fi
