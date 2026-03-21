# pkg/tools/exit.go 詳細設計

## 対象ソース
- `pkg/tools/exit.go`

## 概要
WebSocket 経由のアシスタントセッションを終了させるための専用ツールである。音声モードまたは assistant モードでのみ LLM のツール一覧へ露出するよう `ActivatableTool` を実装している。

## 責務
- 終了用メッセージを `type=exit` として送信する。
- 現在のチャネル・チャット ID 文脈を保持する。
- 入力モードに応じてツールの有効/無効を切り替える。

## 主要な型・関数・メソッド
### `type ExitTool struct`
- `sendCallback SendCallbackWithType`
- `channel string`
- `chatID string`
- `inputMode string`

### 主なメソッド
- `NewExitTool() *ExitTool`
- `SetContext(channel, chatID string)`
- `SetSendCallback(cb SendCallbackWithType)`
- `SetInputMode(mode string)`
- `IsActive() bool`
- `Execute(ctx, args) *ToolResult`

## 詳細動作
- `IsActive` は `inputMode == "voice" || inputMode == "assistant"` のときのみ true を返す。
- `Execute` は以下を順に確認する。
  1. `sendCallback` が設定済みか
  2. `channel` と `chatID` が設定済みか
  3. `message` 引数を任意文字列として取得
- 送信時は `sendCallback(channel, chatID, message, "exit")` を呼ぶ。
- コールバックの戻り値エラーは破棄され、成功扱いで `SilentResult("Exit signal sent.")` を返す。

## 入出力・副作用・永続化
- 入力: `message`、実行前に注入されたチャネル文脈、入力モード、送信コールバック。
- 出力: 無言成功結果またはエラー結果。
- 副作用: WebSocket などチャネル実装への終了シグナル送信。
- 永続化: なし。

## 依存関係
- 標準ライブラリ: `context`
- 同一パッケージ: `SilentResult`, `ErrorResult`
- 関連型: `SendCallbackWithType` は `pkg/tools/android.go` で定義される。

## エラーハンドリング・制約
- コールバック未設定時は `exit tool: send callback not configured` を返す。
- 会話文脈が未設定時は `exit tool: no active channel context` を返す。
- コールバックエラーを返却しない設計のため、送信失敗があってもこのツール単体では検知できない。
