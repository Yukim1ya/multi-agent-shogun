#!/usr/bin/env bash
# dashboard_write.sh — dashboard.md をセクション単位または全体で排他更新する
#
# Edit ツールは karo/gunshi の同時書き込みで "Error editing file" を起こすため
# dashboard.md の更新には必ずこのスクリプトを使うこと。
#
# ── モード ──────────────────────────────────────────────────────────────
#
#  [1] section モード  ─ ## セクションを丸ごと置換（標準入力で新内容を渡す）
#      bash scripts/dashboard_write.sh section "## 進行中" << 'EOF'
#      ## 進行中
#      ...新しい内容...
#      EOF
#
#      セクション境界: <header> 行から次の "^## " 行（または EOF）まで
#      セクション未存在: ファイル末尾に追記
#
#  [2] full モード  ─ ファイル全体を置換（標準入力で新内容を渡す）
#      bash scripts/dashboard_write.sh full << 'EOF'
#      # Dashboard
#      ...
#      EOF
#
#  [3] timestamp モード  ─ "最終更新:" 行だけを現在時刻で更新（引数なし）
#      bash scripts/dashboard_write.sh timestamp
#
# ────────────────────────────────────────────────────────────────────────

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DASHBOARD="$SCRIPT_DIR/dashboard.md"
LOCKFILE="${DASHBOARD}.lock"
LOCK_DIR="${LOCKFILE}.d"

MODE="${1:-}"
SECTION_HEADER="${2:-}"

if [ -z "$MODE" ]; then
    echo "Usage: dashboard_write.sh <section|full|timestamp> [section_header]" >&2
    exit 1
fi

[ ! -f "$DASHBOARD" ] && touch "$DASHBOARD"

# stdin を一時ファイルに退避（ロック取得前に読んでおく）
TMP_CONTENT=$(mktemp)
trap 'rm -f "$TMP_CONTENT"' EXIT
cat > "$TMP_CONTENT"

# ── ロック取得 ────────────────────────────────────────────────────────
_acquire_lock() {
    if command -v flock &>/dev/null; then
        exec 200>"$LOCKFILE"
        flock -w 10 200 || return 1
    else
        local i=0
        while ! mkdir "$LOCK_DIR" 2>/dev/null; do
            sleep 0.1; i=$((i+1)); [ $i -ge 100 ] && return 1
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

# ── Python スクリプト（外部ファイルとして実行）────────────────────────
PY_SCRIPT=$(mktemp --suffix=.py)
trap 'rm -f "$TMP_CONTENT" "$PY_SCRIPT"' EXIT

cat > "$PY_SCRIPT" << 'PYEOF'
import sys, re, os, tempfile, datetime

dashboard_path = sys.argv[1]
mode           = sys.argv[2]
section_header = sys.argv[3] if len(sys.argv) > 3 else ""
content_path   = sys.argv[4]

with open(content_path, encoding="utf-8") as f:
    new_content = f.read()

with open(dashboard_path, encoding="utf-8") as f:
    current = f.read()

if mode == "full":
    result = new_content

elif mode == "timestamp":
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    result = re.sub(r"最終更新:.*", f"最終更新: {now}", current)

elif mode == "section":
    if not section_header:
        print("ERROR: section_header required for section mode", file=sys.stderr)
        sys.exit(1)

    lines = current.splitlines(keepends=True)
    new_lines = (new_content.rstrip("\n") + "\n").splitlines(keepends=True)

    # セクション開始行を検索
    start_idx = None
    for i, line in enumerate(lines):
        stripped = line.rstrip("\n")
        if stripped == section_header or stripped.startswith(section_header + " "):
            start_idx = i
            break

    if start_idx is None:
        # セクション未存在 → 末尾に追記
        result = current.rstrip("\n") + "\n\n" + new_content.rstrip("\n") + "\n"
    else:
        # 終端: 次の "^## " 行または EOF
        end_idx = len(lines)
        for i in range(start_idx + 1, len(lines)):
            if re.match(r"^## ", lines[i]):
                end_idx = i
                break
        result = "".join(lines[:start_idx] + new_lines + lines[end_idx:])

else:
    print(f"ERROR: unknown mode '{mode}'", file=sys.stderr)
    sys.exit(1)

# atomic write
tmp_fd, tmp_path = tempfile.mkstemp(
    dir=os.path.dirname(os.path.abspath(dashboard_path)), suffix=".tmp"
)
try:
    with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
        f.write(result)
    os.replace(tmp_path, dashboard_path)
except Exception:
    try:
        os.unlink(tmp_path)
    except Exception:
        pass
    raise
PYEOF

# ── ロック付き実行（最大3リトライ）────────────────────────────────────
attempt=0
while [ $attempt -lt 3 ]; do
    if _acquire_lock; then
        "$SCRIPT_DIR/.venv/bin/python3" "$PY_SCRIPT" \
            "$DASHBOARD" "$MODE" "$SECTION_HEADER" "$TMP_CONTENT"
        STATUS=$?
        _release_lock
        exit $STATUS
    else
        attempt=$((attempt+1))
        if [ $attempt -lt 3 ]; then
            sleep 0.5
        else
            echo "[dashboard_write] lock timeout for $DASHBOARD" >&2
            exit 1
        fi
    fi
done
