# pkg/tools/message.go 詳細設計

## 対象ソース
- `pkg/tools/message.go`

## 概要
LLM からの明示的なメッセージ送信要求をチャネル実装へ橋渡しするツールである。現行会話チャネルへの返信だけでなく、別チャネルへの送信や `app` エイリアス経由の Android セッション解決も担当する。

## 責務
- メッセージ本文と送信先チャネル/チャット ID を解決する。
- `app` 指定時に最後の Android WebSocket セッションへ変換する。
- クロスチャネル送信時の既知 chat_id を `StateResolver` から引く。
- 送信成功時はユーザー通知を抑止し、重複送信を避ける。

## 主要な型・関数・メソッド
### `type SendCallback`
- `func(channel, chatID, content string) error`

### `type StateResolver interface`
- `GetLastMainChannel() string`
- `GetChannelChatID(channel string) string`

### `type MessageTool struct`
- `sendCallback`, `defaultChannel`, `defaultChatID`, `enabledChannels`, `stateResolver`
- `NewMessageTool() *MessageTool`
- `SetEnabledChannels(channels []string)`
- `SetStateResolver(sr StateResolver)`
- `SetContext(channel, chatID string)`
- `SetSendCallback(callback SendCallback)`
- `Execute(ctx, args) *ToolResult`

## 詳細動作
- `Parameters` の `channel` 説明文は `enabledChannels` が設定済みなら動的に詳細化される。
- `Execute` は `content` を必須とする。
- `channel == "app"` かつ `stateResolver != nil` の場合、`GetLastMainChannel()` の戻り値を `channel:chatID` 形式とみなして分解する。
- `channel` 未指定時は `SetContext` で保持した既定チャネルを使う。
- 別チャネルを指定したが `chat_id` が未指定の場合、`GetChannelChatID(channel)` で既知の相手先を補完する。
- それでも `chat_id` を解決できないクロスチャネル送信は安全のため拒否する。
- 送信成功時は `Silent=true` の `ToolResult` を返す。ユーザーには既に実メッセージが届いている前提である。

## 入出力・副作用・永続化
- 入力: `content`, 任意の `channel` / `chat_id`, 既定文脈、状態解決器、送信コールバック。
- 出力: 無言成功結果またはエラー結果。
- 副作用: チャネル API へのメッセージ送信。
- 永続化: なし。ただし送信先解決で永続状態リーダーを参照する。

## 依存関係
- 標準ライブラリ: `context`, `fmt`, `strings`
- 同一パッケージ: `ToolResult`
- 実装先例: チャネルマネージャや永続状態管理層

## エラーハンドリング・制約
- `content` 未指定、送信先未解決、コールバック未設定時はエラー。
- `app` エイリアス解決は `mainCh` が `"channel:chatID"` 形式であることを前提にしている。
- クロスチャネル送信では既知の chat_id が無い限り誤配送防止のため送信しない。
