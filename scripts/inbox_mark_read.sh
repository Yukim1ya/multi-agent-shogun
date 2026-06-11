#!/usr/bin/env bash
# inbox_mark_read.sh — inboxの全未読エントリをread: trueにする（排他ロック付き）
# Usage: bash scripts/inbox_mark_read.sh <agent_name>
# Example: bash scripts/inbox_mark_read.sh karo
#
# inbox_write.sh と同じ flock + atomic rename パターンを使用。
# Claude Code の Edit ツールは inbox_watcher.sh との競合で "Error editing file" を
# 引き起こすため、既読マークには必ずこのスクリプトを使うこと。

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$1"

if [ -z "$TARGET" ]; then
    echo "Usage: inbox_mark_read.sh <agent_name>" >&2
    exit 1
fi

INBOX="$SCRIPT_DIR/queue/inbox/${TARGET}.yaml"
LOCKFILE="${INBOX}.lock"

[ ! -f "$INBOX" ] && exit 0

LOCK_DIR="${LOCKFILE}.d"

_acquire_lock() {
    if command -v flock &>/dev/null; then
        exec 200>"$LOCKFILE"
        flock -w 5 200 || return 1
    else
        local i=0
        while ! mkdir "$LOCK_DIR" 2>/dev/null; do
            sleep 0.1
            i=$((i + 1))
            [ $i -ge 50 ] && return 1
        done
    fi
    return 0
}

_release_lock() {
    if command -v flock &>/dev/null; then
        exec 200>&-
    else
        rmdir "$LOCK_DIR" 2>/dev/null
    fi
}

attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    if _acquire_lock; then
        "$SCRIPT_DIR/.venv/bin/python3" - "$INBOX" "$TARGET" << 'PYEOF'
import yaml, sys, tempfile, os

inbox_path, target = sys.argv[1], sys.argv[2]

with open(inbox_path) as f:
    data = yaml.safe_load(f)

if not data or not data.get('messages'):
    sys.exit(0)

changed = sum(1 for m in data['messages'] if not m.get('read', False))
if changed == 0:
    sys.exit(0)

for msg in data['messages']:
    msg['read'] = True

tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(inbox_path), suffix='.tmp')
try:
    with os.fdopen(tmp_fd, 'w') as f:
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
    os.replace(tmp_path, inbox_path)
except Exception:
    os.unlink(tmp_path)
    raise

print(f'[inbox_mark_read] {changed} message(s) marked as read for {target}', file=sys.stderr)
PYEOF
        STATUS=$?
        _release_lock
        exit $STATUS
    else
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            sleep 0.5
        else
            echo "[inbox_mark_read] Failed to acquire lock for $INBOX" >&2
            exit 1
        fi
    fi
done
