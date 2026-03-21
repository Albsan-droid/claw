# line.go 詳細設計

## 対象ソース
- `pkg/channels/line.go`

## 概要
LINE Official Account 用チャネル実装。受信側は HTTP Webhook サーバとして動作し、送信側は LINE Messaging API の Reply API / Push API を使う。グループでは Bot 宛メンション時のみ処理し、返信トークンや quote token を一時保持して応答最適化を行う。

## 責務
- LINE Webhook サーバの起動・停止
- Webhook 署名検証
- Bot 情報取得によるメンション判定補助
- 受信イベントの非同期処理
- Reply API 優先・Push API フォールバック送信
- 画像/音声/動画の取得と一時ファイル管理
- ローディング表示の送信

## 主要な型・関数・メソッド
### 定数
- API ベース URL、Reply/Push/Content/BotInfo/Loading 各 endpoint
- `lineReplyTokenMaxAge = 25 * time.Second`

### `type replyTokenEntry struct`
- `token string`
- `timestamp time.Time`

### `type LINEChannel struct`
- `*BaseChannel`
- `config config.LINEConfig`
- `httpServer *http.Server`
- `botUserID`, `botBasicID`, `botDisplayName`
- `replyTokens sync.Map`
- `quoteTokens sync.Map`
- `ctx context.Context`
- `cancel context.CancelFunc`

### `NewLINEChannel(cfg config.LINEConfig, messageBus *bus.MessageBus) (*LINEChannel, error)`
- `ChannelSecret` と `ChannelAccessToken` の両方必須。

### `Start(ctx context.Context) error`
- `fetchBotInfo` で Bot プロフィールを取得する。
- `WebhookPath` が空なら `/webhook/line` を使う。
- `http.Server` を生成し、goroutine で `ListenAndServe` を開始する。

### `fetchBotInfo() error`
- `GET /info` を呼び、`userId`, `basicId`, `displayName` を保持する。

### `Stop(ctx context.Context) error`
- cancel 実行後、5 秒タイムアウト付きで `httpServer.Shutdown` を行う。

### `webhookHandler(w, r)`
- POST のみ許可。
- request body 読み出し後、`X-Line-Signature` を `verifySignature` で検証する。
- JSON を `payload.Events` へデコードする。
- 200 を先に返し、各イベントは goroutine で `processEvent` する。

### `processEvent(event lineEvent)`
- `type != "message"` は無視する。
- source から `senderID` / `chatID` を決定する。
- グループ/ルームでは `isBotMentioned` が真のときだけ処理する。
- reply token / quote token を `sync.Map` に保存する。
- メッセージ種別別に本文・メディアを組み立てる。
- `sendLoading(senderID)` 後に `HandleMessage` する。

### `isBotMentioned(msg lineMessage) bool`
- mention metadata 内の `all` または `userId` 一致を優先判定する。
- 一致しなくても `displayName` を使ったテキスト一致にフォールバックする。

### `stripBotMention(text, msg)`
- mention metadata の index/length を使ってメンション文字列を除去する。
- 失敗時は `@<displayName>` の単純置換にフォールバックする。

### `Send(ctx, msg)`
- quote token を取り出して削除する。
- reply token が 25 秒以内なら `sendReply` を試す。
- reply 失敗または期限切れなら `sendPush` する。

### 補助関数
- `resolveChatID`
- `buildTextMessage`
- `sendReply`
- `sendPush`
- `sendLoading`
- `callAPI`
- `downloadContent`

## 詳細動作
### 起動
1. 必須設定がある場合のみインスタンス生成できる。
2. `Start` で Bot 情報取得を試みる。
3. 取得失敗時もチャネル起動は継続し、メンション検知精度のみ下がる。
4. Webhook サーバを指定 host/port/path で待受開始する。

### Webhook 受信
1. POST 以外は 405 を返す。
2. body 読み取り失敗・JSON 解析失敗は 400 を返す。
3. 署名不正は 403 を返す。
4. 正常時は即座に 200 を返し、LINE 側タイムアウトを避ける。
5. 各イベントは非同期処理されるため、Webhook 応答時間と本処理を分離している。

### メッセージ処理
- `text`: 本文を取り込み、グループなら Bot メンションを除去する。
- `image`: ダウンロード後に Data URL 化できれば `mediaPaths` へ追加する。
- `audio`: ダウンロードファイルパスを `mediaPaths` に入れ、本文に `[audio]` を設定する。
- `video`: ダウンロードファイルパスを `mediaPaths` に入れ、本文に `[video]` を設定する。
- `file`: 本文 `[file]`
- `sticker`: 本文 `[sticker]`
- その他: `[<type>]`

### 送信
- 返信可能期間内は Reply API を優先するため、Push API 消費を抑える設計。
- 返信トークン使用後は `LoadAndDelete` により消費される。
- quote token も 1 回の応答に使うと削除される。

## 入出力・副作用・永続化
### 入力
- LINE Webhook HTTP リクエスト
- LINE Messaging API 応答
- `bus.OutboundMessage`

### 出力
- `MessageBus` への `InboundMessage`
- LINE Reply API / Push API / Loading API への HTTP POST
- Webhook HTTP レスポンス

### 副作用
- HTTP サーバ起動/停止
- 外部 API 呼び出し
- `replyTokens` / `quoteTokens` の更新
- 一時ファイルの作成・削除
- ログ出力

### 永続化
- 永続化なし。
- reply token / quote token はメモリ上の `sync.Map` のみ。
- メディアは一時ファイルとして保存後、defer で削除する。

## 依存関係
- 標準: `bytes`, `context`, `crypto/hmac`, `crypto/sha256`, `encoding/base64`, `encoding/json`, `fmt`, `io`, `net/http`, `os`, `strings`, `sync`, `time`
- 内部: `pkg/bus`, `pkg/config`, `pkg/logger`, `pkg/utils`

## エラーハンドリング・制約
- 起動時に `channel_secret` / `channel_access_token` 欠如なら生成失敗。
- Bot 情報取得失敗は Warning のみで継続する。
- API エラーは HTTP ステータスとレスポンス本文を含む `error` として返す。
- `sendLoading` 失敗は Debug ログのみで継続する。
- グループ/ルームでは Bot メンションがないメッセージを処理しない。
- `replyTokens` / `quoteTokens` はプロセス再起動で失われる。

