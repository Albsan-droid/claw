# pkg/i18n/messages_channel.go 詳細設計

## 対象ソース
- `pkg/i18n/messages_channel.go`

## 概要
`messages_channel.go` はメッセージングチャネルおよびチャットコマンドに関する固定文言を英語/日本語で登録する。Telegram 向けの `/help` 系、WebSocket 初期文言、Agent ループの `/show` `/list` `/switch` 応答が含まれる。

## 責務
- チャネル UI/UX メッセージの翻訳辞書登録
- Telegram コマンド応答文の保持
- Agent loop のチャネル/モデル切替メッセージ保持

## 主要な型・関数・メソッド
- `func init()`
- 主な登録キー
  - `channel.thinking`
  - `channel.config_required`
  - `cmd.help`, `cmd.start`
  - `cmd.show.*`, `cmd.list.*`
  - `agent.cmd.show.*`, `agent.cmd.list.*`, `agent.cmd.switch.*`, `agent.cmd.channel_mgr_error`

## 詳細動作
- `init()` は英語・日本語の2辞書を `register()` に渡す。
- キー群の役割:
  - `channel.thinking` — Telegram 等で「考え中」を示す一時メッセージ
  - `channel.config_required` — WebSocket 側で設定未完了を伝える文言
  - `cmd.help` — `/start` `/help` `/show` `/list` の使い方を複数行文字列で返す
  - `cmd.show.*` / `cmd.list.*` — Telegram の簡易管理コマンド向け応答
  - `agent.cmd.show.*` / `agent.cmd.list.*` / `agent.cmd.switch.*` — Agent loop で扱うチャット内コマンド向け応答
- いくつかのキーは共有目的で重複を避けている。
  - コメント上、`cmd.show.usage` と `cmd.list.usage` は Telegram commands と Agent loop commands で共有される。
- `%s` プレースホルダ付きキーが多く、チャネル名・モデル名・未知パラメータ名などを呼び出し側で埋め込む。

## 入出力・副作用・永続化
- 入力
  - package 初期化時の固定メッセージ定義
- 出力
  - `pkg/i18n.messages` への登録
- 永続化
  - なし
- 副作用
  - グローバル翻訳辞書更新

## 依存関係
- `pkg/i18n/i18n.go` の `register()`

## エラーハンドリング・制約
- メッセージは静的定義であり、チャネル機能有無との整合性検証はしない。
- `/switch` 系メッセージには「現在は存在確認のみ」と明記されており、実装仕様に依存する説明が埋め込まれている。
- `%s` 付き文字列は呼び出し側の引数数に依存する。
