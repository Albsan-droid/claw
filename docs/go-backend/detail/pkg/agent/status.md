# pkg/agent/status.go

## 対象ソース
- `pkg/agent/status.go`

## 概要
ツール実行中にユーザーへ見せる短いステータス文を、ツール名・引数・ロケールから組み立てる。翻訳自体は `pkg/i18n` に委譲し、このファイルは「どのキーをどう選ぶか」の分岐を持つ。

## 責務
- ツール別ステータス文言の選択
- 引数付き文言のフォーマット
- Android / memory / skill / cron / MCP 用の個別分岐
- URL / パス / 文字列の見やすい要約

## 主要な型・関数・メソッド
- `statusLabel(toolName string, args map[string]interface{}, locale string) string`
- `fileStatusLabel(locale, baseKey, fmtKey string, args map[string]interface{}) string`
- `memoryStatusLabel(args map[string]interface{}, locale string) string`
- `skillStatusLabel(args map[string]interface{}, locale string) string`
- `cronStatusLabel(args map[string]interface{}, locale string) string`
- `androidStatusLabel(args map[string]interface{}, locale string) string`
- `mcpStatusLabel(args map[string]interface{}, locale string) string`
- `strArg(args map[string]interface{}, key string) string`
- `truncLabel(s string, maxRunes int) string`
- `hostFromURL(rawURL string) string`

## 詳細動作
### `statusLabel`
- `toolName` を `switch` し、対応する i18n キーを選ぶ。
- 主な対象ツール
  - `web_search`, `web_fetch`
  - `read_file`, `write_file`, `edit_file`, `append_file`, `list_dir`
  - `exec`
  - `memory`, `skill`, `cron`
  - `message`, `spawn`, `subagent`
  - `android`, `exit`, `mcp`
- 未知のツールは `status.processing` を返す。

### 補助分岐
- `fileStatusLabel` は `path` があれば `filepath.Base(path)` を使う。
- `memoryStatusLabel` は `action` に応じて `read_long_term`, `read_daily`, `write_long_term`, `append_daily` を出し分ける。
- `skillStatusLabel` は `skill_list`, `skill_read` を扱う。
- `cronStatusLabel` は `add`, `list`, `remove` を扱う。
- `androidStatusLabel` は `search_apps`, `app_info`, `launch_app`, `screenshot`, `get_ui_tree`, `tap`, `swipe`, `text`, `keyevent`, `broadcast`, `intent` を扱う。
- `mcpStatusLabel` は `mcp_list`, `mcp_tools`, `mcp_call` を扱う。

### 文字列整形
- `strArg` は `args[key]` が文字列型のときだけ返す。
- `hostFromURL` は `url.Parse` 成功時に `Host` を返し、失敗時は生文字列を `truncLabel(..., 30)` で短縮する。
- `truncLabel` は **`maxRunes` 文字まで切ったあとに `...` を付ける** 実装であり、戻り値の長さは切り詰め後に最大 `maxRunes + 3` 文字になりうる。

## 入出力・副作用・永続化
### 入力
- ツール名
- ツール引数マップ
- ロケール文字列

### 出力
- ローカライズ済みの短いステータス文

### 副作用
- なし（翻訳テーブル参照のみ）

### 永続化
- なし

## 依存関係
- `pkg/i18n`
- 標準ライブラリ: `net/url`, `path/filepath`, `unicode/utf8`

## エラーハンドリング・制約
- 引数が欠けていても基本文言へフォールバックする。
- `strArg` は文字列以外を無視するため、数値や bool はそのままでは表示されない。
- URL パース失敗は例外にせず、生文字列の短縮表示に落とす。
