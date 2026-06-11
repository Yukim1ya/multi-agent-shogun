#!/usr/bin/env bash
# new_blog_article.sh — 技術ブログ記事作成パイプラインを1コマンドで起動する
#
# 使い方:
#   bash scripts/new_blog_article.sh --topic "テーマ"
#   bash scripts/new_blog_article.sh --topic "テーマ" --dry-run
#
# topic だけ指定すればよい。topic_area・対象読者・注意事項は
# 企画作成足軽が topic をもとに自律的に決定する。
#
# 実行すると:
#   1. queue/tasks/cmd_blog_XXX.yaml を自動採番して作成
#   2. 家老のinboxに cmd_new メッセージを送信（--dry-run 時はスキップ）
#   3. 進捗確認コマンドを表示
#
# --dry-run: YAMLの生成・内容確認のみ行い、家老への送信はしない

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/queue/tasks"

# ---- 引数パース ----
topic=""
dry_run=false

usage() {
  cat << 'USAGE'
使い方:
  bash scripts/new_blog_article.sh --topic <テーマ> [--dry-run]

必須:
  --topic      記事テーマ

オプション:
  --dry-run    YAMLの生成・確認のみ行い、家老への送信はしない

例:
  bash scripts/new_blog_article.sh --topic "Splunk で Kerberoasting を検知する"
  bash scripts/new_blog_article.sh --topic "Nutanix CE の初期セットアップ手順" --dry-run
USAGE
  exit 1
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --topic)    topic="$2"; shift 2 ;;
    --dry-run)  dry_run=true; shift ;;
    -h|--help)  usage ;;
    *) echo "エラー: 不明なオプション: $1" >&2; usage ;;
  esac
done

[[ -z "$topic" ]] && { echo "エラー: --topic は必須です" >&2; usage; }

# ---- cmd_blog_XXX を自動採番 ----
next_blog_num() {
  local max=0
  for f in "$TASKS_DIR"/cmd_blog_*.yaml; do
    [[ -f "$f" ]] || continue
    # ^cmd_blog_NNN$ にのみマッチ。cmd_blog_008_redo.yaml 等のサフィックス付きは除外
    local num num_dec
    num=$(basename "$f" .yaml | grep -oP '^cmd_blog_\K\d+$')
    [[ -z "$num" ]] && continue
    num_dec=$(( 10#$num ))  # 先頭ゼロを10進数として扱う（008をoctalと誤解しない）
    [[ "$num_dec" -gt "$max" ]] && max=$num_dec
  done
  printf "%03d" $((max + 1))
}

CMD_NUM=$(next_blog_num)
CMD_ID="cmd_blog_${CMD_NUM}"
CMD_FILE="$TASKS_DIR/${CMD_ID}.yaml"

# ---- YAMLの内容を生成（文字列として）----
YAML_CONTENT=$(python3 - "$CMD_ID" "$topic" << 'PYEOF'
import sys
import json
from datetime import datetime

cmd_id, topic = sys.argv[1:]

def q(s):
    return json.dumps(s, ensure_ascii=False)

now = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")

print(f"""\
# 技術ブログ記事作成パイプライン
# 生成: new_blog_article.sh | {now}
cmd_id: {cmd_id}
type: blog_pipeline
project: tech_blog
project_context: context/tech_blog.md
status: open
created_by: shogun
created_at: {q(now)}

title: {q("技術記事作成: " + topic)}

article_request:
  topic: {q(topic)}
  # topic_area / target_reader / notes は企画作成足軽が topic をもとに決定する

pipeline:
  phase1_proposal:
    status: pending
    assigned_to: null
    reviewer: null
    gunshi_verdict: null     # approved | revision_needed
    retry_count: 0
    max_retries: 3
    last_revision_points: []

  phase2_article:
    status: pending
    assigned_to: null
    reviewer: null
    gunshi_verdict: null
    output_file: null        # articles/YYYYMMDD_<slug>.md
    retry_count: 0
    max_retries: 3
    last_revision_points: []

  phase3_upload:
    status: pending
    github_url: null

acceptance_criteria:
  - "軍師がarticle_writingの成果物をapprovedと判定していること"
  - "articles/ ディレクトリに記事Markdownがコミットされていること"
  - "github_url が dashboard.md に記録されていること"

karo_instructions: |
  context/tech_blog.md の「パイプライン定義」セクションを参照して実行せよ。

  将軍が指定したテーマ: {topic}

  企画作成足軽はテーマをもとに以下を自律的に決定すること:
  - topic_area（splunk / ad_attack / nutanix / riss / general）
  - target_reader（想定読者）
  - outline（記事構成）
  - differentiation（差別化ポイント）
  - hashtags

  Phase 1（企画）→ Phase 2（執筆）→ Phase 3（GitHubアップロード）の順で進め、
  各フェーズで足軽と軍師のレビューを経ること。
""", end="")
PYEOF
)

# ---- dry-run の場合はYAML内容を表示して終了（ファイルは作成しない）----
if $dry_run; then
  echo ""
  echo "[DRY RUN] ファイル作成・家老への送信はしていません。内容を確認してください:"
  echo "  生成予定ファイル: $CMD_FILE"
  echo "---"
  echo "$YAML_CONTENT"
  echo "---"
  echo ""
  echo "問題なければ以下を実行して本番送信:"
  echo "  bash scripts/new_blog_article.sh --topic $(printf '%q' "$topic")"
  exit 0
fi

# ---- YAMLファイルをディスクに書き込み ----
echo "$YAML_CONTENT" > "$CMD_FILE"
echo "[new_blog_article] 作成: $CMD_FILE" >&2

# ---- 家老のinboxに送信 ----
bash "$SCRIPT_DIR/inbox_write.sh" karo \
  "${CMD_ID}を書いた。queue/tasks/${CMD_ID}.yaml を読んでtech_blogパイプラインを実行せよ。" \
  cmd_new shogun

# ---- 完了メッセージ ----
echo ""
echo "パイプライン起動完了"
echo "  cmd_id : $CMD_ID"
echo "  topic  : $topic"
echo "  file   : $CMD_FILE"
echo ""
echo "進捗確認:"
echo "  cat $REPO_ROOT/dashboard.md"
