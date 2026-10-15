#!/usr/bin/env bash
set -euo pipefail

LABEL="app.reviewwatcher"

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/Applications/ReviewWatcher.app"

echo "removed the agent and the app."
echo "config and state kept — delete them with:"
echo "  rm -rf ~/.config/reviewwatcher ~/.local/state/reviewwatcher"
