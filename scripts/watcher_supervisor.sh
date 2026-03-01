#!/usr/bin/env bash
set -euo pipefail

# Keep inbox watchers alive in a persistent tmux-hosted shell.
# This script is designed to run forever.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

mkdir -p logs queue/inbox

ensure_inbox_file() {
    local agent="$1"
    if [ ! -f "queue/inbox/${agent}.yaml" ]; then
        printf 'messages: []\n' > "queue/inbox/${agent}.yaml"
    fi
}

pane_exists() {
    local pane="$1"
    tmux list-panes -a -F "#{session_name}:#{window_name}.#{pane_index}" 2>/dev/null | grep -qx "$pane"
}

start_watcher_if_missing() {
    local agent="$1"
    local pane="$2"
    local log_file="$3"
    local cli

    ensure_inbox_file "$agent"
    if ! pane_exists "$pane"; then
        return 0
    fi

    # Count active watchers — kill excess if multiple exist (Bug 2 fix)
    local watcher_count
    watcher_count=$(pgrep -cf "inbox_watcher.sh ${agent} " 2>/dev/null || echo 0)

    if [ "$watcher_count" -gt 1 ]; then
        echo "[$(date)] WARNING: $watcher_count watchers for $agent, killing excess..." >&2
        # Kill all except the oldest (first PID)
        pgrep -f "inbox_watcher.sh ${agent} " 2>/dev/null | tail -n +2 | xargs -r kill 2>/dev/null || true
        sleep 1
    fi

    if [ "$watcher_count" -ge 1 ]; then
        return 0
    fi

    cli=$(tmux show-options -p -t "$pane" -v @agent_cli 2>/dev/null || echo "codex")
    nohup bash scripts/inbox_watcher.sh "$agent" "$pane" "$cli" >> "$log_file" 2>&1 &
}

while true; do
    start_watcher_if_missing "shogun" "shogun:main.0" "logs/inbox_watcher_shogun.log"
    start_watcher_if_missing "karo"      "multiagent:agents.0"   "logs/inbox_watcher_karo.log"
    start_watcher_if_missing "gunshi"    "multiagent:agents.1"   "logs/inbox_watcher_gunshi.log"
    start_watcher_if_missing "ashigaru1" "multiagent:ashigaru.0" "logs/inbox_watcher_ashigaru1.log"
    start_watcher_if_missing "ashigaru2" "multiagent:ashigaru.1" "logs/inbox_watcher_ashigaru2.log"
    start_watcher_if_missing "ashigaru3" "multiagent:ashigaru.2" "logs/inbox_watcher_ashigaru3.log"
    start_watcher_if_missing "ashigaru4" "multiagent:ashigaru.3" "logs/inbox_watcher_ashigaru4.log"
    start_watcher_if_missing "ashigaru5" "multiagent:ashigaru.4" "logs/inbox_watcher_ashigaru5.log"
    start_watcher_if_missing "ashigaru6" "multiagent:ashigaru.5" "logs/inbox_watcher_ashigaru6.log"
    start_watcher_if_missing "ashigaru7" "multiagent:ashigaru.6" "logs/inbox_watcher_ashigaru7.log"
    sleep 5
done
