#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# completion_notifier.sh — 足軽タスク完了をリアルタイムで将軍に通知
#
# 機能:
#   - queue/reports/ashigaru*_report.yaml を監視
#   - status: completed を初めて検出したら:
#     1. logs/completions.log にタイムスタンプ付きで記録
#     2. shogun の tmux pane にビープ音を送信
#     3. tmux display-message でステータスバーに完了通知を表示
#     4. ntfy が設定されていればプッシュ通知を送信
#
# Usage:
#   bash scripts/completion_notifier.sh &
#   → watcher_supervisor.sh から自動起動される
#
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORTS_DIR="$SCRIPT_DIR/queue/reports"
LOG_FILE="$SCRIPT_DIR/logs/completions.log"
STATE_FILE="/tmp/completion_notifier_state"
SHOGUN_PANE="shogun:main.0"

mkdir -p "$SCRIPT_DIR/logs"
touch "$LOG_FILE"
touch "$STATE_FILE"

# ─── 完了済みタスクを state ファイルから読み込む ───
load_notified() {
    cat "$STATE_FILE" 2>/dev/null || true
}

# ─── 完了通知済みとしてマーク ───
mark_notified() {
    local key="$1"
    echo "$key" >> "$STATE_FILE"
}

# ─── 既に通知済みかチェック ───
is_notified() {
    local key="$1"
    grep -qxF "$key" "$STATE_FILE" 2>/dev/null
}

# ─── レポートファイルを解析して完了通知 ───
check_report() {
    local file="$1"
    [ -f "$file" ] || return 0

    local agent
    agent=$(basename "$file" _report.yaml)

    # status: completed の行を探す（YAML の最上位フィールドのみ）
    local status
    status=$(grep -m1 "^status:" "$file" 2>/dev/null | awk '{print $2}' | tr -d '"' | tr -d "'" || echo "")
    [ "$status" = "completed" ] || return 0

    # task_id を取得
    local task_id
    task_id=$(grep -m1 "^task_id:" "$file" 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "unknown")

    # 通知のキー（agent + task_id の組み合わせ）
    local key="${agent}:${task_id}"
    if is_notified "$key"; then return 0; fi

    # タイムスタンプ
    local ts
    ts=$(date '+%H:%M:%S')
    local date_str
    date_str=$(date '+%Y-%m-%d')

    # title があれば取得
    local title
    title=$(grep -m1 "^title:" "$file" 2>/dev/null | sed 's/^title: *//' | tr -d '"' || echo "")
    [ -z "$title" ] && title="$task_id"

    # エージェント番号を短縮表示
    local agent_short="${agent/ashigaru/足軽}"

    local msg="[$ts] ✅ ${agent_short} 完了 — ${title}"

    # ── 1. ログファイルに記録 ──
    echo "$msg" >> "$LOG_FILE"
    echo "[${date_str} ${ts}] ${agent}: ${task_id} | ${title}" >> "$LOG_FILE.detail"

    # ── 2. shogun pane にビープ音 ──
    # tmux でターゲット pane の tty を特定し、BEL 文字を直接書き込む
    if tmux list-panes -a -F "#{session_name}:#{window_name}.#{pane_index}" 2>/dev/null | grep -qx "$SHOGUN_PANE"; then
        local shogun_tty
        shogun_tty=$(tmux list-panes -a \
            -F "#{session_name}:#{window_name}.#{pane_index} #{pane_tty}" 2>/dev/null \
            | awk -v p="$SHOGUN_PANE" '$1==p {print $2}')
        if [ -n "$shogun_tty" ] && [ -w "$shogun_tty" ]; then
            # BEL文字を3回（ビープ3回）
            printf '\a\a\a' >> "$shogun_tty" 2>/dev/null || true
        fi
    fi

    # ── 3. tmux ステータスバーに表示（5秒間） ──
    tmux display-message -t "$SHOGUN_PANE" -d 5000 "$msg" 2>/dev/null || true

    # ── 4. ntfy プッシュ通知（設定されている場合のみ） ──
    local ntfy_topic
    ntfy_topic=$(grep 'ntfy_topic:' "$SCRIPT_DIR/config/settings.yaml" 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "")
    if [ -n "$ntfy_topic" ] && [ -f "$SCRIPT_DIR/scripts/ntfy.sh" ]; then
        bash "$SCRIPT_DIR/scripts/ntfy.sh" "$msg" 2>/dev/null || true
    fi

    # ── 5. 通知済みとしてマーク ──
    mark_notified "$key"

    echo "[$(date '+%H:%M:%S')] [completion_notifier] 通知送信: $msg" >&2
}

# ─── 全レポートを一括チェック ───
check_all_reports() {
    for f in "$REPORTS_DIR"/ashigaru*_report.yaml; do
        if [ -f "$f" ]; then check_report "$f"; fi
    done
}

# ─── メインループ ───
main() {
    echo "[$(date '+%H:%M:%S')] [completion_notifier] 起動 (PID $$)" >&2

    # 起動時に既存の完了済みを state に記録（再起動後の重複通知防止）
    for f in "$REPORTS_DIR"/ashigaru*_report.yaml; do
        [ -f "$f" ] || continue
        local_status=$(grep -m1 "^status:" "$f" 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "")
        if [ "$local_status" = "completed" ]; then
            local local_agent local_task_id local_key
            local_agent=$(basename "$f" _report.yaml)
            local_task_id=$(grep -m1 "^task_id:" "$f" 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "unknown")
            local_key="${local_agent}:${local_task_id}"
            # 起動時の既存完了は通知せずマークのみ
            is_notified "$local_key" || mark_notified "$local_key"
        fi
    done

    echo "[$(date '+%H:%M:%S')] [completion_notifier] 初期スキャン完了、監視開始" >&2

    # inotifywait バイナリを解決（~/.local/bin にインストール済みの場合も考慮）
    # WSL2 の /mnt/c/ パスは Linux inotify 非対応のためポーリングに強制
    local INOTIFY_BIN=""
    if [[ "$REPORTS_DIR" != /mnt/* ]]; then
        if [ -x "${HOME}/.local/bin/inotifywait" ]; then
            INOTIFY_BIN="${HOME}/.local/bin/inotifywait"
        elif command -v inotifywait &>/dev/null; then
            INOTIFY_BIN="$(command -v inotifywait)"
        fi
    fi

    if [ -n "$INOTIFY_BIN" ]; then
        echo "[$(date '+%H:%M:%S')] [completion_notifier] inotifywait 使用: $INOTIFY_BIN" >&2
        while true; do
            local changed_file
            changed_file=$(LD_LIBRARY_PATH="${HOME}/.local/lib:${LD_LIBRARY_PATH:-}" \
                "$INOTIFY_BIN" -q -t 30 -e close_write --format '%f' \
                "$REPORTS_DIR" 2>/dev/null || echo "")

            if [[ "$changed_file" == *_report.yaml ]]; then
                check_report "$REPORTS_DIR/$changed_file"
            else
                # タイムアウト（30s）or 空 → 安全網として全スキャン
                check_all_reports
            fi
        done
    else
        # WSL2 /mnt/ パス or inotifywait なし → ポーリング（10秒ごと）
        echo "[$(date '+%H:%M:%S')] [completion_notifier] polling mode (10s interval)" >&2
        while true; do
            check_all_reports
            sleep 10
        done
    fi
}

# ─── Signal handler ───
trap 'echo "[$(date)] [completion_notifier] 終了" >&2; exit 0' SIGTERM SIGINT

main
