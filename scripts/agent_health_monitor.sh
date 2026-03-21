#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# agent_health_monitor.sh — エージェント自動復旧スクリプト
#
# 機能:
#   - 全エージェントの稼働状態を監視（60秒ループ）
#   - Claude Code落ち検出（pane_current_command = "bash"）
#   - 自動再起動と状態確認
#   - 未読inboxがあればnudge送信
#   - ロック機構で重複起動を防止
#   - 再起動上限 2回/5分 で過度な自動復旧を防止
#
# Usage:
#   bash scripts/agent_health_monitor.sh &
#   echo $! > /tmp/agent_health_monitor.pid
#
# Termination:
#   kill $(cat /tmp/agent_health_monitor.pid)
#
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${PROJECT_ROOT}/logs"
LOG_FILE="${LOG_DIR}/health_monitor.log"
INBOX_DIR="${PROJECT_ROOT}/queue/inbox"
LOCK_DIR="/tmp/health_monitor_locks"

# Create necessary directories
mkdir -p "$LOG_DIR" "$LOCK_DIR"

# ─── ログ関数 ───
log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"
    if [ "$level" = "RECOVER" ]; then
        echo "[$timestamp] [$level] $msg" >&2
    fi
}

# ─── エージェント定義（pane → agent_id マッピング）───
# 参考: shutsujin_departure.sh の tmux セッション構成
declare -A AGENT_PANES=(
    [multiagent:agents.0]="karo"
    [multiagent:agents.1]="gunshi"
    [multiagent:ashigaru.0]="ashigaru1"
    [multiagent:ashigaru.1]="ashigaru2"
    [multiagent:ashigaru.2]="ashigaru3"
    [multiagent:ashigaru.3]="ashigaru4"
    [multiagent:ashigaru.4]="ashigaru5"
    [multiagent:ashigaru.5]="ashigaru6"
    [multiagent:ashigaru.6]="ashigaru7"
)

# ─── 再起動タイムスタンプ管理 ───
# ファイル: /tmp/health_monitor_locks/{agent_id}.restarts
# フォーマット: 1行に1つのタイムスタンプ（UNIX time）
get_recent_restarts() {
    local agent_id="$1"
    local window=300  # 5分（秒）
    local now=$(date +%s)
    local restart_file="${LOCK_DIR}/${agent_id}.restarts"
    local count=0

    if [ ! -f "$restart_file" ]; then
        echo 0
        return
    fi

    while IFS= read -r timestamp; do
        local age=$((now - timestamp))
        if [ $age -lt $window ]; then
            ((count++))
        fi
    done < "$restart_file"

    echo $count
}

# 再起動タイムスタンプを記録
record_restart() {
    local agent_id="$1"
    local restart_file="${LOCK_DIR}/${agent_id}.restarts"
    echo "$(date +%s)" >> "$restart_file"
}

# 古い再起動記録をクリーンアップ
cleanup_old_restarts() {
    local agent_id="$1"
    local window=300  # 5分
    local now=$(date +%s)
    local restart_file="${LOCK_DIR}/${agent_id}.restarts"
    local tmp_file="${restart_file}.tmp"

    if [ ! -f "$restart_file" ]; then
        return
    fi

    > "$tmp_file"
    while IFS= read -r timestamp; do
        local age=$((now - timestamp))
        if [ $age -lt $window ]; then
            echo "$timestamp" >> "$tmp_file"
        fi
    done < "$restart_file"

    mv "$tmp_file" "$restart_file"
}

# ─── ロック機構 ───
# 同時実行を防ぐためのロック
acquire_lock() {
    local agent_id="$1"
    local lock_file="${LOCK_DIR}/${agent_id}.lock"
    local timeout=30
    local elapsed=0

    while [ -f "$lock_file" ] && [ $elapsed -lt $timeout ]; do
        sleep 0.5
        ((elapsed++))
    done

    if [ -f "$lock_file" ]; then
        return 1
    fi

    echo $$ > "$lock_file"
    return 0
}

release_lock() {
    local agent_id="$1"
    local lock_file="${LOCK_DIR}/${agent_id}.lock"
    rm -f "$lock_file"
}

# ─── Pane状態確認 ───
get_pane_command() {
    local pane="$1"

    if ! tmux list-panes -t "$pane" -F "#{pane_current_command}" 2>/dev/null; then
        echo "UNKNOWN"
    fi
}

# ─── 未読inboxチェック ───
has_unread_inbox() {
    local agent_id="$1"
    local inbox_file="${INBOX_DIR}/${agent_id}.yaml"

    if [ ! -f "$inbox_file" ]; then
        return 1
    fi

    # read: false が存在するかチェック
    grep -q "read: false" "$inbox_file" 2>/dev/null && return 0
    return 1
}

# ─── Nudge送信 ───
send_nudge() {
    local pane="$1"
    local agent_id="$2"

    # nudgeテキストを送信（Enterとは分離）
    local unread_count=0
    local inbox_file="${INBOX_DIR}/${agent_id}.yaml"

    if [ -f "$inbox_file" ]; then
        unread_count=$(grep -c "read: false" "$inbox_file" 2>/dev/null || echo 0)
    fi

    if [ $unread_count -gt 0 ]; then
        tmux send-keys -t "$pane" "inbox${unread_count}" Enter 2>/dev/null || true
        log "NUDGE" "Sent nudge to $agent_id ($unread_count unread)"
    fi
}

# ─── エージェント再起動 ───
restart_agent() {
    local agent_id="$1"
    local pane="$2"

    # ロック取得
    if ! acquire_lock "$agent_id"; then
        log "WARN" "Could not acquire lock for $agent_id, skipping restart"
        return 1
    fi

    trap "release_lock '$agent_id'" RETURN

    # 再起動上限チェック
    cleanup_old_restarts "$agent_id"
    local recent_count=$(get_recent_restarts "$agent_id")

    if [ $recent_count -ge 2 ]; then
        log "WARN" "Too many restarts for $agent_id (2 in last 5min), skipping"
        return 1
    fi

    # switch_cli.sh で再起動
    log "RECOVER" "$agent_id is down (was: bash), restarting..."

    if bash "${PROJECT_ROOT}/scripts/switch_cli.sh" "$agent_id" > /dev/null 2>&1; then
        record_restart "$agent_id"
        log "OK" "$agent_id restarted"

        # 再起動後の復帰確認を待機
        sleep 30

        # 復帰確認
        local final_cmd=$(get_pane_command "$pane")
        if [ "$final_cmd" = "claude" ]; then
            log "HEALTHY" "$agent_id is running (claude)"

            # 未読inboxがあればnudgeを送信
            if has_unread_inbox "$agent_id"; then
                sleep 2
                send_nudge "$pane" "$agent_id"
            fi

            return 0
        else
            log "WARN" "$agent_id failed to recover (command: $final_cmd)"
            return 1
        fi
    else
        log "WARN" "Failed to restart $agent_id via switch_cli.sh"
        return 1
    fi
}

# ─── メインループ ───
main_loop() {
    log "INFO" "agent_health_monitor started (PID $$)"

    local loop_interval=60

    while true; do
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

        # 全エージェントのチェック
        for pane in "${!AGENT_PANES[@]}"; do
            local agent_id="${AGENT_PANES[$pane]}"
            local current_cmd

            current_cmd=$(get_pane_command "$pane" 2>/dev/null || echo "UNKNOWN")

            if [ "$current_cmd" = "bash" ]; then
                # Claude Code落ち検出
                log "WARN" "$agent_id is down (pane_current_command: bash)"
                restart_agent "$agent_id" "$pane"
            fi
        done

        # 全エージェントがOKの場合
        log "INFO" "Health check completed (all agents ok)"

        sleep "$loop_interval"
    done
}

# ─── Signal handlers ───
cleanup() {
    log "INFO" "agent_health_monitor stopping (PID $$)"
    exit 0
}

trap cleanup SIGTERM SIGINT SIGHUP

# ─── メイン実行 ───
main_loop
