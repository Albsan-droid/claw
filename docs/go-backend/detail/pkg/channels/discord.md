# discord.go 詳細設計

## 対象ソース
- `pkg/channels/discord.go`

## 概要
Discord Bot を用いたチャネル実装。Discord から受信したメッセージや添付ファイルを `MessageBus` に流し、バックエンドからの応答を Discord メッセージとして返す。長文送信時は Discord の文字数制限を考慮して分割する。

## 責務
- Discord セッション生成・開始・終了
- 受信メッセージの購読と allowlist 判定
- 添付ファイルの一時ダウンロードとメディア抽出
- Discord 送信時の長文分割とタイムアウト制御

## 主要な型・関数・メソッド
### `type DiscordChannel struct`
- `*BaseChannel`
- `session *discordgo.Session`
- `config config.DiscordConfig`
- `ctx context.Context`

### `NewDiscordChannel(cfg config.DiscordConfig, bus *bus.MessageBus) (*DiscordChannel, error)`
- `discordgo.New("Bot " + cfg.Token)` でセッションを作成する。
- 失敗時は `failed to create discord session` を返す。

### `Start(ctx context.Context) error`
- `handleMessage` をハンドラ登録する。
- `session.Open()` で接続し、`setRunning(true)` する。
- `session.User("@me")` で Bot 情報を取得してログする。

### `Stop(ctx context.Context) error`
- `session.Close()` で切断し、`running=false` にする。

### `Send(ctx context.Context, msg bus.OutboundMessage) error`
- 稼働中でない場合は失敗。
- `msg.ChatID` を Discord の channel ID として利用する。
- `msg.Content` を `splitMessage(content, 1500)` で分割し、各チャンクを `sendChunk` で送信する。

### `splitMessage(content string, limit int) []string`
- 改行・空白を優先して分割位置を決める。
- コードブロック ``` が未閉鎖になる場合は、可能なら閉じ側まで延長し、無理ならコードブロック直前で切る。

### `sendChunk(ctx context.Context, channelID, content string) error`
- `context.WithTimeout(ctx, 10*time.Second)` を使い送信タイムアウトを設ける。
- 実送信は goroutine 内で `ChannelMessageSend` を呼び、select で完了/タイムアウトを待つ。

### `handleMessage(s *discordgo.Session, m *discordgo.MessageCreate)`
- 自分自身の発言は無視する。
- typing indicator を送る。
- allowlist に通らない送信者は拒否する。
- 添付ファイルを `downloadAttachment` で保存し、可能なら Data URL 化する。
- `metadata` を構築して `HandleMessage` に渡す。

### 補助関数
- `findLastUnclosedCodeBlock`
- `findNextClosingCodeBlock`
- `findLastNewline`
- `findLastSpace`
- `appendContent`
- `downloadAttachment`

## 詳細動作
### 起動
1. コンストラクタで Discord API セッションを生成する。
2. `Start` でイベントハンドラを登録する。
3. `Open` 成功後に Bot 自身のユーザー情報を取得し、接続完了ログを出す。

### 受信
1. `handleMessage` が Discord イベントを受ける。
2. Bot 自身のメッセージはループ防止のため除外する。
3. `ChannelTyping` を送って応答中表示を出す。
4. allowlist 判定後、添付ファイルをローカルへダウンロードする。
5. `utils.EncodeFileToDataURL` に成功すれば `mediaPaths` に格納する。
6. Data URL 化できない場合は本文へ `[audio: filename]` を追記する。
7. `guild_id` が空かどうかで DM を判定する。
8. `BaseChannel.HandleMessage` を通じて `InboundMessage` 化する。

### 送信
1. `Send` は文字数 0 の本文を送らない。
2. 長文は 1500 文字目安で分割する。
3. 各チャンクは 10 秒以内に Discord API へ送る。
4. いずれかのチャンク送信失敗で全体を失敗扱いにする。

## 入出力・副作用・永続化
### 入力
- Discord Gateway イベント
- `bus.OutboundMessage`
- Discord 添付ファイル URL

### 出力
- Discord へのテキストメッセージ送信
- `MessageBus` への `InboundMessage` 投入

### 副作用
- Discord API / Gateway 通信
- typing indicator の送信
- 添付ファイルの一時保存と削除
- ログ出力

### 永続化
- 永続化はしない。
- 添付ファイルは一時ファイルとして保存し、defer で削除する。

## 依存関係
- `github.com/bwmarrin/discordgo`
- `github.com/KarakuriAgent/clawdroid/pkg/bus`
- `github.com/KarakuriAgent/clawdroid/pkg/config`
- `github.com/KarakuriAgent/clawdroid/pkg/logger`
- `github.com/KarakuriAgent/clawdroid/pkg/utils`
- `context`, `fmt`, `os`, `strings`, `time`

## エラーハンドリング・制約
- Discord セッション生成・Open・Close・送信失敗は `error` として返す。
- 受信ハンドラ内の typing indicator 失敗や一時ファイル削除失敗はログのみで継続する。
- allowlist 不一致は silently skip に近い挙動で、ログは Debug のみ。
- 送信分割ロジックは Markdown 構造を完全には解釈せず、``` ベースの簡易保護に留まる。
- `ctx` キャンセルまたは 10 秒超過で `sendChunk` はタイムアウト失敗する。

