#!/usr/bin/env bash
set -euo pipefail

LABEL="app.reviewwatcher"
APP_NAME="ReviewWatcher"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config/reviewwatcher"
INSTALL_DIR="$HOME/Applications"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/reviewwatcher.log"

if [[ ! -d "$ROOT/build/$APP_NAME.app" ]]; then
    "$ROOT/build.sh"
fi

command -v glab >/dev/null || { echo "glab is not installed: brew install glab" >&2; exit 1; }

mkdir -p "$CONFIG_DIR" "$INSTALL_DIR" "$(dirname "$PLIST")"

if [[ ! -f "$CONFIG_DIR/config.json" ]]; then
    # plutil reads JSON and ships with every macOS; jq only does from macOS 15.
    username="$(glab api user | plutil -extract username raw -o - - 2>/dev/null || true)"
    [[ -n "$username" ]] || { echo "could not read your GitLab username; check 'glab auth status'" >&2; exit 1; }
    cat > "$CONFIG_DIR/config.json" <<JSON
{
  "host": "${GITLAB_HOST:-gitlab.com}",
  "username": "$username",
  "pollIntervalSeconds": 60,
  "notifyOnNewReviewRequest": true,
  "notifyOnApprovalRemoved": true,
  "notifyOnPipelineFixed": true,
  "notifyOnActivity": false,
  "notifyBacklogOnFirstRun": false,
  "notifyOnlyWhen": { "pipeline": "any", "noConflicts": false, "notDraft": false },
  "collapsedFilePatterns": ["*test*", "*spec/*"]
}
JSON
    echo "wrote $CONFIG_DIR/config.json for @$username"
else
    echo "kept existing $CONFIG_DIR/config.json"
fi

if [[ ! -f "$CONFIG_DIR/token" ]]; then
    if [[ -n "${GITLAB_TOKEN:-}" ]]; then
        printf '%s' "$GITLAB_TOKEN" > "$CONFIG_DIR/token"
    else
        read -rsp "GitLab personal access token (api scope): " token && echo
        printf '%s' "$token" > "$CONFIG_DIR/token"
    fi
    chmod 600 "$CONFIG_DIR/token"
    echo "stored token in $CONFIG_DIR/token (mode 600)"
else
    echo "kept existing $CONFIG_DIR/token"
fi

rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$ROOT/build/$APP_NAME.app" "$INSTALL_DIR/"

cat > "$PLIST" <<PLIST_XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>$INSTALL_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key>
    <dict><key>SuccessfulExit</key><false/></dict>
    <key>ThrottleInterval</key><integer>30</integer>
    <key>StandardErrorPath</key><string>$LOG</string>
    <key>StandardOutPath</key><string>$LOG</string>
</dict>
</plist>
PLIST_XML

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
# bootout returns before the old agent is gone, and bootstrapping over it fails with error 5.
for _ in {1..20}; do
    launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1 || break
    sleep 0.5
done
launchctl bootstrap "gui/$UID" "$PLIST"

echo
echo "installed. approve the notification prompt if macOS shows one."
echo "  log:    $LOG"
echo "  config: $CONFIG_DIR/config.json"
