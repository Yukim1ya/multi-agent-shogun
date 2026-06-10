# tech-blog プロジェクトコンテキスト
最終更新: 2026-06-10

## 基本情報
- **プロジェクトID**: tech_blog
- **投稿媒体**: note.com
- **GitHubリポジトリ**: https://github.com/Yukim1ya/side-business-plan (private)
- **記事保存パス**: `articles/` ディレクトリ（リポジトリルート直下）
- **目的**: 専門知識を活かした技術記事を定期投稿し、副業収益を得る

## 筆者プロフィール（記事に反映すること）
- 専門領域: Splunk、Active Directory攻撃検知（Blue Team）、Nutanix CE
- 立場: 実務経験に基づいた解説を提供するセキュリティエンジニア

## 扱うトピック領域
| 領域 | 具体例 |
|------|--------|
| Splunk | SPLクエリ集、検知ルール設計、ダッシュボード構築 |
| AD攻撃検知 | Kerberoasting/Pass-the-Hash/Golden Ticket の検知と対策 |
| Nutanix | CE構築手順、運用Tips、よくあるエラーと解決策 |
| 汎用セキュリティ | インシデント対応手順、ISMS準備、ゼロトラスト入門 |

---

## 記事フォーマット仕様（note.com向け）

### 必須構成
```
# 記事タイトル（H1・検索キーワードを含める）

導入文（3〜5行）
- この記事で何が分かるか
- 想定読者
- 筆者の経験一言

## セクション1（H2）
...

## セクション2（H2）
...

## まとめ
- 箇条書き3〜5点で要点を整理

#ハッシュタグ1 #ハッシュタグ2 #ハッシュタグ3
```

### 数値基準
| 項目 | 基準値 |
|------|--------|
| 文字数 | 1500〜4000字（日本語） |
| H2セクション数 | 2〜5個 |
| コードブロック | 技術系記事は最低1個必須 |
| ハッシュタグ | 3〜5個 |

### コードブロック形式
````
```splunk
index=windows EventCode=4625 | stats count by src_ip
```
````
言語指定を必ず付ける（splunk / powershell / bash / python / yaml 等）

---

## パイプライン定義

### フェーズ1: 企画作成・レビュー

**足軽（企画作成）の役割**:

将軍が指定するのは `topic`（テーマ）のみ。
それ以外の項目はすべて足軽が topic をもとに自律的に決定する。

決定すべき項目:
- `topic_area`: テーマが最も近い領域を選ぶ（splunk / ad_attack / nutanix / general）
- `target_reader`: 誰が読むと最も価値があるかを具体的に定義する
- `title`: 検索キーワードを含む具体的なタイトル案
- `outline`: 読者が得るものを最大化する記事構成
- `differentiation`: 既存記事との差別化ポイント
- `hashtags`: note.com で発見されやすいタグ

**足軽（企画作成）のアウトプット形式**:
```yaml
proposal:
  title: "記事タイトル案（検索キーワード含む）"
  topic_area: "splunk | ad_attack | nutanix | general"
  target_reader: "想定読者（具体的に）"
  hook: "なぜ今これを書くか・読者が得るもの（2〜3行）"
  outline:
    - "## セクション1タイトル"
    - "## セクション2タイトル"
    - "## まとめ"
  differentiation: "他の記事との差別化ポイント"
  estimated_chars: 2000
  hashtags:
    - "#Splunk"
    - "#セキュリティ"
```

**足軽（一次レビュー）の確認項目**:
- [ ] タイトルに検索キーワードが含まれているか
- [ ] 対象読者が具体的か（「エンジニア一般」は不可）
- [ ] アウトラインに「まとめ」セクションが含まれているか
- [ ] 差別化ポイントが明確か
- [ ] 筆者のトピック領域（上記）に合致しているか

NG時: 家老のinboxに報告すること。足軽が直接作成者に差し戻し禁止。家老が `retry_count` をインクリメントしredoタスクを生成する。

**軍師レビューの観点**:
- SEO・発見可能性: タイトルで狙うキーワードは検索需要があるか
- 独自性: 同じ内容の記事がすでに大量にあるなら差別化が必要
- 実現可能性: 足軽が実際に書ける内容か（調査や実機検証が必要かどうか）
- 判定: `approved` / `revision_needed`

`revision_needed` 時は報告YAMLに以下を必ず含めること（家老がredoタスクの `redo_constraints` に引き継ぐ）:
```yaml
gunshi_verdict: revision_needed
revision_points:
  - "指摘内容（修正方針を含む具体的な記述）"
  - "例: タイトルが汎用的すぎる。差別化ポイントと矛盾している"
```

### フェーズ2: 記事執筆・レビュー

**足軽（記事執筆）の成果物**:
- Markdown形式の記事本文（上記フォーマット仕様に準拠）
- ファイル名: `articles/YYYYMMDD_<slug>.md`（例: `articles/20260610_splunk_spl_cheat.md`）

**足軽（一次レビュー）の確認項目**:
- [ ] 文字数が1500〜4000字の範囲内か
- [ ] H1タイトルが企画案のタイトルと一致しているか
- [ ] 導入文に「この記事で分かること・想定読者」が含まれているか
- [ ] 全H2セクションが企画アウトライン通りに存在するか
- [ ] 「まとめ」セクションがあり、3点以上の要点が箇条書きされているか
- [ ] コードブロックに言語指定があるか
- [ ] ハッシュタグが3〜5個付いているか
- [ ] 明らかな誤字・脱字がないか

NG時: 家老のinboxに報告すること。足軽が直接執筆者に差し戻し禁止。家老が `retry_count` をインクリメントしredoタスクを生成する。

**軍師レビューの観点**:
- 内容の正確性: 技術的に誤った記述がないか（特にコマンド・クエリ）
- 実践的価値: 読んですぐ試せる具体性があるか
- 文章品質: 論理の流れが自然か、読みやすいか
- 企画との一致: 承認された企画案の意図が記事に反映されているか
- 判定: `approved` / `revision_needed`

`revision_needed` 時は報告YAMLに以下を必ず含めること（家老がredoタスクの `redo_constraints` に引き継ぐ）:
```yaml
gunshi_verdict: revision_needed
revision_points:
  - "指摘内容（修正方針を含む具体的な記述）"
  - "例: SPLクエリのフィールド名が実際のEventLogと一致しない。field=src_ip → src を使うべき"
```

### フェーズ3: GitHubアップロード（家老）

軍師承認後、家老が以下を実行する:
```bash
export PATH="$HOME/.local/bin:$PATH"
# side-business-planリポジトリのローカルクローンがない場合はクローン
# git clone https://github.com/Yukim1ya/side-business-plan.git /tmp/side-business-plan

# articles/ディレクトリに記事ファイルをコミット・プッシュ
gh api repos/Yukim1ya/side-business-plan/contents/articles/<filename> \
  --method PUT \
  --field message="feat(article): <タイトル>" \
  --field content="$(base64 -w 0 <filepath>)"
```

---

## リトライ・エスカレーション仕様（全フェーズ共通）

- 全NGは**家老経由**でルーティングする。足軽・軍師が直接差し戻し禁止
- 家老はパイプラインYAMLの `retry_count` をインクリメントし、redoタスクを生成する
- `retry_count` が `max_retries`（3）を超えた場合、家老は `dashboard.md` の「🚨要対応」セクションに記載して将軍の判断を仰ぐ
- 軍師の `revision_points` は家老がredoタスクの `redo_constraints` フィールドにそのまま引き継ぐ

パイプラインYAMLのリトライ管理フィールド（家老が更新）:
```yaml
phase1_proposal:
  retry_count: 0        # NGのたびに家老がインクリメント
  max_retries: 3        # 超過時は将軍エスカレ
  last_revision_points: []  # 軍師の直近revision_pointsをコピー

phase2_article:
  retry_count: 0
  max_retries: 3
  last_revision_points: []
```

---

## 品質基準サマリー

| フェーズ | 担当 | NG時の対応 |
|---------|------|-----------|
| 企画一次レビュー | 別の足軽 | 家老に報告 → 家老がredoタスク生成（retry_count++） |
| 企画軍師レビュー | 軍師 | revision_points付きで家老に報告 → 家老がredoタスク生成（retry_count++） |
| 記事一次レビュー | 別の足軽 | 家老に報告 → 家老がredoタスク生成（retry_count++） |
| 記事軍師レビュー | 軍師 | revision_points付きで家老に報告 → 家老がredoタスク生成（retry_count++） |
| retry_count > 3 | 家老 | dashboard「🚨要対応」に記載、将軍判断待ち |
| GitHubアップロード | 家老 | コミット後、URLを将軍ダッシュボードに記載 |

---

## 注意事項
- 事実確認が必要なコマンド・クエリは「※動作確認要」と明記し、創作しない
- note.com はコードブロックをそのまま貼付可能。Markdown全機能は使えないため図表はテキスト代替で対応
