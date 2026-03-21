# pkg/i18n/messages_status.go 詳細設計

## 対象ソース
- `pkg/i18n/messages_status.go`

## 概要
`messages_status.go` はバックエンドが処理中ステータスとして表示する `status.*` メッセージ群を英語/日本語で登録する。ツール実行、ファイル操作、MCP、Cron、Android 操作など広いサブシステムの進捗文言をここで一元管理する。

## 責務
- ステータス表示メッセージの `en` / `ja` カタログ登録
- `%s` 付き詳細ステータス文言の定義
- サブシステム別キー群の整理

## 主要な型・関数・メソッド
- `func init()`
- 主なキー群
  - 基本: `status.thinking`, `status.processing`, `status.interrupted`
  - Web: `status.searching*`, `status.fetching_*`
  - ファイル: `status.reading_file*`, `status.writing_file*`, `status.editing_file*`, `status.appending_file*`
  - ディレクトリ/exec: `status.listing_dir*`, `status.running_command*`
  - Memory: `status.memory_*`
  - Skill: `status.skill_*`
  - Cron: `status.cron_*`
  - Message: `status.sending_message`
  - Spawn/Subagent: `status.spawn*`, `status.subagent*`
  - Android: `status.android_*`
  - Exit: `status.exit`
  - MCP: `status.mcp_*`

## 詳細動作
- `init()` で `register("en", ...)` と `register("ja", ...)` を実行する。
- `*_q` サフィックスのキーは `%s` を1つ受け取る詳細版。
  - 例: `status.searching_q`, `status.running_command_q`, `status.skill_read_q`
- `status.mcp_call_sq` だけは `%s/%s` を受け取る二変数版。
- Android 系は action 名に対応した進捗文言を持つ。
  - `status.android_search_apps`
  - `status.android_app_info(_q)`
  - `status.android_launch_app(_q)`
  - `status.android_screenshot`
  - `status.android_get_ui_tree`
  - `status.android_tap`
  - `status.android_swipe`
  - `status.android_text`
  - `status.android_keyevent(_q)`
  - `status.android_broadcast`
  - `status.android_intent`
  - `status.android_default`
- サブシステムごとに「個別キーが無い時のデフォルト」も用意している。
  - `status.memory_default`
  - `status.skill_default`
  - `status.cron_default`
  - `status.android_default`
  - `status.mcp_default`

## 入出力・副作用・永続化
- 入力
  - package 初期化時の固定メッセージ
- 出力
  - `pkg/i18n.messages` への `status.*` 登録
- 永続化
  - なし
- 副作用
  - グローバル翻訳辞書更新

## 依存関係
- `pkg/i18n/i18n.go` の `register()`

## エラーハンドリング・制約
- 静的 map 登録のみで、キー重複や未使用キーの検証はしない。
- `%s` / `%s/%s` を含むキーは、呼び出し側が `Tf()` で正しい個数の引数を渡す前提。
- 新しいツール種別を追加した場合、本ファイルに対応キーを足さないとフォールバックや未翻訳キー表示が起こりうる。
