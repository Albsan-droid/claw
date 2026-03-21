# telegram.go 詳細設計

## 対象ソース
- `pkg/channels/telegram.go`

## 概要
Telegram Bot の long polling 実装。通常メッセージとコマンドを受信し、応答時には一時的な「thinking」メッセージを編集または通常送信する。Markdown 風の出力を Telegram HTML へ変換する補助機能も持つ。

## 責務
- Telegram Bot 初期化（任意プロキシ対応）
- long polling と handler 登録
- 通常メッセージの受信処理
- thinking 表示とプレースホルダ管理
- 写真/音声/音楽/文書の取得
- Markdown→Telegram HTML 変換

## 主要な型・関数・メソッド
### `type TelegramChannel struct`
- `*BaseChannel`
- `bot *telego.Bot`
- `commands TelegramCommander`
- `config *config.Config`
- `chatIDs map[string]int64`
- `placeholders sync.Map`
- `stopThinking sync.Map`

### `type thinkingCancel struct`
- `fn context.CancelFunc`
- `Cancel()` で nil 安全にキャンセルする。

### `NewTelegramChannel(cfg, bus)`
- `cfg.Channels.Telegram.Proxy` が設定されていれば HTTP client の Proxy を差し込む。
- `telego.NewBot` で Bot を作成する。
- `NewTelegramCommands` でコマンド実装を関連付ける。

### `Start(ctx)`
- `UpdatesViaLongPolling` で更新ストリームを開始する。
- `th.NewBotHandler` を生成する。
- `/help`, `/start`, `/show`, `/list` をコマンドハンドラに紐付ける。
- `th.AnyMessage()` は `handleMessage` で受ける。
- `bh.Start()` を goroutine で開始し、`ctx.Done()` 時に `bh.Stop()` する。

### `Stop(ctx)`
- `running=false` にする。Bot の明示停止 API 呼び出しはない。

### `Send(ctx, msg)`
- `msg.ChatID` を `parseChatID` で int64 化する。
- `stopThinking` に入っているキャンセル関数を実行し、thinking 状態を止める。
- `markdownToTelegramHTML` で HTML 化する。
- プレースホルダ messageID があれば `EditMessageText` を試す。
- 編集失敗時は通常の `SendMessage` にフォールバックする。
- HTML parse 失敗時は plain text にフォールバックする。

### `handleMessage(ctx, message)`
- nil や送信者欠落は `error` を返す。
- senderID は `userID|username` 形式も取りうる。
- allowlist 不一致なら終了する。
- テキスト、caption、photo、voice、audio、document を統合処理する。
- ChatActionTyping とローカライズ済み thinking 文言を送る。
- `metadata` を構築し `HandleMessage` に渡す。

### ファイル取得系
- `downloadPhoto`
- `downloadFileWithInfo`
- `downloadFile`

### 変換・補助関数
- `parseChatID`
- `markdownToTelegramHTML`
- `extractCodeBlocks`
- `extractInlineCodes`
- `escapeHTML`

## 詳細動作
### 起動
1. 必要に応じて Proxy 付き HTTP クライアントを作成する。
2. long polling を 30 秒タイムアウトで開始する。
3. コマンドと通常メッセージを 1 つの BotHandler に登録する。
4. `ctx` 終了時に handler を停止する。

### 受信処理
1. 送信者がいないメッセージは異常として `error` を返す。
2. allowlist 判定に通った場合のみ、メディアダウンロードへ進む。
3. 写真は最大サイズの要素を選ぶ。
4. Voice は `.ogg`、Audio は `.mp3`、Document は拡張子指定なしでダウンロードする。
5. 写真は Data URL 化を試し、音声や文書はローカルパスを `mediaPaths` に入れる。
6. 本文が空でメディアもない場合は `[empty message]` を設定する。
7. typing action を送り、さらに thinking メッセージを送って placeholder として保持する。
8. ロケールは `message.From.LanguageCode` から `localeFromMessage` で決める。
9. `HandleMessage` 呼び出し時の senderID は `fmt.Sprintf("%d", user.ID)` であり、username 付き複合 ID ではない点に注意が必要。

### 応答送信
- 既存 placeholder があれば、そのメッセージを応答本文へ差し替える。
- 編集失敗時や placeholder 不在時は新規メッセージを送る。
- HTML モード失敗時は ParseMode を外して再送する。

### Markdown→HTML 変換
- コードブロックとインラインコードを先にプレースホルダへ退避する。
- 見出しや引用記法を平文化する。
- HTML エスケープ後にリンク、太字、斜体、打消し、箇条書きを変換する。
- 最後にコードブロック/インラインコードを `<pre><code>` / `<code>` として戻す。

## 入出力・副作用・永続化
### 入力
- Telegram updates
- Telegram File API
- `bus.OutboundMessage`

### 出力
- `MessageBus` への `InboundMessage`
- Telegram への typing action / thinking メッセージ / 応答メッセージ

### 副作用
- long polling 実行
- `placeholders` / `stopThinking` / `chatIDs` 更新
- 一時ファイル作成と削除
- ログ出力

### 永続化
- 永続化なし
- thinking 状態や placeholder はメモリ上のみ
- ダウンロードファイルは一時保存後削除

## 依存関係
- `github.com/mymmrac/telego`
- `github.com/mymmrac/telego/telegohandler`
- `github.com/mymmrac/telego/telegoutil`
- `pkg/bus`, `pkg/config`, `pkg/i18n`, `pkg/logger`, `pkg/utils`
- `context`, `fmt`, `net/http`, `net/url`, `os`, `regexp`, `strings`, `sync`, `time`

## エラーハンドリング・制約
- Proxy URL 不正、Bot 生成失敗、polling 開始失敗、handler 作成失敗は即 `error` を返す。
- 受信処理中のチャットアクション送信失敗はログのみで継続する。
- placeholder 編集失敗時は自動的に新規送信へフォールバックする。
- `chatIDs` map へのアクセスはロック保護されていない。
- `Stop` は `running` を落とすのみで、外部から `ctx` を止める前提で polling を終わらせる設計である。

