# websocket.go 詳細設計

## 対象ソース
- `pkg/channels/websocket.go`

## 概要
クライアント APK などからの WebSocket 接続を受け入れるサーバ側チャネル実装。双方向リアルタイム通信を担い、切断時には Android broadcast へのフォールバックも行う。加えて、デバイスツール応答の横取り処理も持つ。

## 責務
- WebSocket サーバ起動・停止
- 接続ごとの clientID / chatID / clientType 管理
- 受信 JSON の `InboundMessage` 化
- 送信 JSON の WebSocket 配信
- 切断 main クライアントへの broadcast フォールバック
- 任意 API key 認証
- config 未作成時の `setup_required` 通知

## 主要な型・関数・メソッド
### `type wsIncoming`
- `Content string`
- `SenderID string`
- `Images []string`
- `InputMode string`
- `Type string`
- `RequestID string`

### `type wsOutgoing`
- `Content string`
- `Type string`

### `type WebSocketChannel struct`
- `*BaseChannel`
- `config config.WebSocketConfig`
- `configPath string`
- `server *http.Server`
- `upgrader websocket.Upgrader`
- `clients map[*websocket.Conn]string`
- `chatConns map[string]*websocket.Conn`
- `clientTypes map[string]string`
- `mu sync.RWMutex`
- `ctx context.Context`
- `cancel context.CancelFunc`

### `NewWebSocketChannel(cfg, msgBus, configPath)`
- `CheckOrigin` は常に `true` の upgrader を作る。
- 各管理 map を初期化する。

### `Start(ctx)`
- `config.Path` に `handleWS` を登録した HTTP サーバを作る。
- goroutine で `ListenAndServe` を開始する。

### `Stop(ctx)`
- `cancel()` 実行後、全接続を Close する。
- 管理 map を空にし、`server.Shutdown(ctx)` で HTTP サーバ停止する。

### `Send(ctx, msg)`
- `msg.ChatID` に対応する connection を探す。
- 接続なし、または送信直前に失効していれば `maybeBroadcast` を試す。
- 送信データは `wsOutgoing{Content, Type}` を JSON 化して送る。

### `maybeBroadcast(msg, clientType, originalErr)`
- `status` / `status_end` は Android broadcast フォールバックしない。
- `clientType == "main"` の場合のみ `broadcast.Send` を使う。
- broadcast も失敗した場合は合成エラーを返す。

### `handleWS(w, r)`
- API key が設定されていれば `api_key` クエリを定数時間比較する。
- `client_id`, `client_type`, `locale` をクエリから受け取る。
- `client_id` 未指定時は UUID を生成する。
- `chatID := "ws:<clientID>"` を採用する。
- 既存同 chatID 接続があれば切断して置き換える。
- `configPath` が存在しなければ `setup_required` メッセージを即送信する。
- `readPump` を goroutine 起動する。

### `GetClientType(chatID)`
- 記録済み clientType を返す。

### `readPump(conn, clientID, chatID, clientType, locale)`
- 接続終了時に `clients`, `chatConns` から除去する。
- `ReadMessage` をループし JSON を `wsIncoming` へデコードする。
- `tool_response` かつ `request_id` 付きなら `tools.DeviceResponseWaiter.Deliver` へ直接渡し、バスには流さない。
- `Images` は `data:image/png;base64,` を前置して Data URL 化する。
- `input_mode`, `client_type`, `locale` を metadata に入れて `HandleMessage` する。

## 詳細動作
### 接続確立
1. 必要なら API key を照合する。
2. WebSocket upgrade に成功したら clientID/clientType/locale を決定する。
3. `chatID=ws:<clientID>` をキーに接続を登録する。
4. 同一 clientID の古い接続があれば上書きし、旧 connection を閉じる。
5. 設定ファイルがまだ無ければ `setup_required` を送る。
6. `readPump` が受信処理専用 goroutine として走る。

### 受信
- JSON 解析失敗はログのみで継続する。
- `SenderID` 未設定時は `clientID` を送信者 ID とする。
- 画像は PNG Data URL 前提で扱う。
- `tool_response` は通常会話ではなくデバイスツール応答として処理される。

### 送信
- 接続中なら対象 connection に直接書き込む。
- すでに切断済みなら、main クライアントに限って Android broadcast へフォールバックする。
- `status` は `channels.Manager` 側で WebSocket 以外に配送されない。
- `status_end` は `channels.Manager` では特別扱いされないため、他チャネルにも送信試行され得る。一方で `maybeBroadcast` は `status` / `status_end` の両方を Android broadcast にフォールバックしない。

## 入出力・副作用・永続化
### 入力
- HTTP/WebSocket 接続要求
- WebSocket テキストメッセージ
- `bus.OutboundMessage`
- `configPath` 上のファイル存在有無

### 出力
- WebSocket テキストメッセージ
- `MessageBus` への `InboundMessage`
- 必要時の Android broadcast
- 401 / upgrade 失敗 / setup_required 等の HTTP/WS 応答

### 副作用
- HTTP サーバ待受
- 接続管理 map 更新
- goroutine 起動
- ログ出力
- `tools.DeviceResponseWaiter` への通知

### 永続化
- 永続化なし
- `clientTypes` は切断後も map 上に残り得る実装で、broadcast 判定用に使われる

## 依存関係
- `context`, `crypto/subtle`, `encoding/json`, `fmt`, `net/http`, `os`, `sync`
- `github.com/gorilla/websocket`
- `github.com/google/uuid`
- `pkg/broadcast`, `pkg/bus`, `pkg/config`, `pkg/i18n`, `pkg/logger`, `pkg/tools`

## エラーハンドリング・制約
- API key 不一致は 401 を返す。
- Upgrade 失敗はログを出して終了する。
- JSON 不正は接続を切らずに継続する。
- `CheckOrigin` が常に true のため、Origin 制約は設けていない。
- 書き込み失敗時、broadcast 条件に合わなければ元の送信エラーを返す。
- `clientTypes` は切断後も削除しない設計であり、履歴的に残る。
