# whatsapp.go 詳細設計

## 対象ソース
- `pkg/channels/whatsapp.go`

## 概要
外部の WhatsApp bridge サービスへ WebSocket クライアントとして接続するチャネル実装。bridge から届くメッセージイベントを内部へ流し、内部応答は bridge プロトコルの JSON として送る。

## 責務
- WhatsApp bridge への接続/切断
- bridge からの受信ループ
- 受信 JSON の簡易解釈と `InboundMessage` 化
- 応答メッセージの JSON 送信

## 主要な型・関数・メソッド
### `type WhatsAppChannel struct`
- `*BaseChannel`
- `conn *websocket.Conn`
- `config config.WhatsAppConfig`
- `url string`
- `mu sync.Mutex`
- `connected bool`

### `NewWhatsAppChannel(cfg, bus)`
- `BridgeURL` を `url` に保持する。

### `Start(ctx)`
- `websocket.DefaultDialer` の `HandshakeTimeout` を 10 秒に設定する。
- `Dial(c.url, nil)` に成功したら connection を保存し、`connected=true`, `running=true` にする。
- `listen(ctx)` を goroutine 起動する。

### `Stop(ctx)`
- connection を閉じ、`conn=nil`, `connected=false`, `running=false` にする。

### `Send(ctx, msg)`
- `conn == nil` なら失敗。
- `{"type":"message","to":msg.ChatID,"content":msg.Content}` を JSON 化して送信する。

### `listen(ctx)`
- `ctx.Done()` まで読み取りを繰り返す。
- connection が無ければ 1 秒 sleep して再試行する。
- `ReadMessage` 失敗時は 2 秒 sleep して継続する。
- JSON を `map[string]interface{}` に展開し、`type == "message"` のときだけ `handleIncomingMessage` を呼ぶ。

### `handleIncomingMessage(msg)`
- `from` を senderID として読む。
- `chat` が無ければ chatID は senderID を使う。
- `content`, `media`, `id`, `from_name` を拾って metadata を構成する。
- `HandleMessage` へ引き渡す。

## 詳細動作
### 起動
1. bridge URL へ WebSocket 接続する。
2. 接続成功後に listen goroutine を開始する。
3. 再接続ロジックはなく、既存 connection を読み続ける構成。

### 受信
- bridge の受信 JSON は厳密な struct ではなく map で扱う。
- `media` は `[]interface{}` を `[]string` へ変換して使う。
- ログには本文先頭 50 文字までを出力する。

### 送信
- 送信プロトコルは type/to/content の 3 フィールドのみ。
- `ctx` 引数は受け取るが、送信処理自体には使っていない。

## 入出力・副作用・永続化
### 入力
- WebSocket bridge からのテキストメッセージ
- `bus.OutboundMessage`

### 出力
- bridge への JSON メッセージ送信
- `MessageBus` への `InboundMessage`

### 副作用
- 外部 WebSocket 接続
- ログ出力
- mutex による排他制御

### 永続化
- なし

## 依存関係
- `context`, `encoding/json`, `fmt`, `log`, `sync`, `time`
- `github.com/gorilla/websocket`
- `pkg/bus`, `pkg/config`, `pkg/utils`

## エラーハンドリング・制約
- 接続失敗は `Start` から `error` を返す。
- 読み取り失敗や JSON 解析失敗はログのみで継続する。
- 自動再接続は実装していないため、connection 断後も `listen` は sleep を挟んで既存 `conn` を参照し続けるだけである。
- `connected` フィールドは更新されるが、送信時の接続判定には `conn != nil` しか使っていない。
- bridge プロトコルは動的 map 解釈のため、型不一致に弱い。

