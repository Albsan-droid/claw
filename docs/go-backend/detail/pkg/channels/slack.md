# slack.go 詳細設計

## 対象ソース
- `pkg/channels/slack.go`

## 概要
Slack Socket Mode を使ったチャネル実装。Slack からのメッセージ、@mention、slash command を受け取り `MessageBus` へ流し、応答は通常メッセージとして投稿する。受信確認として eyes / white_check_mark リアクションも付与する。

## 責務
- Slack API/Socket Mode クライアント生成
- Socket Mode イベントループ運用
- 通常メッセージ・mention・slash command の処理
- 添付ファイルダウンロード
- スレッド対応 chatID の解釈
- 処理中/完了リアクションの付与

## 主要な型・関数・メソッド
### `type SlackChannel struct`
- `*BaseChannel`
- `config config.SlackConfig`
- `api *slack.Client`
- `socketClient *socketmode.Client`
- `botUserID string`
- `ctx context.Context`
- `cancel context.CancelFunc`
- `pendingAcks sync.Map`

### `type slackMessageRef struct`
- `ChannelID string`
- `Timestamp string`

### `NewSlackChannel(cfg, messageBus)`
- `BotToken` と `AppToken` が必須。
- `slack.New` と `socketmode.New` を構築する。

### `Start(ctx)`
- `AuthTest` で認証確認し、自 Bot の user ID を保持する。
- `eventLoop` と `socketClient.RunContext` を goroutine 起動する。
- 稼働状態を true にする。

### `Stop(ctx)`
- cancel 実行後 `running=false` にする。

### `Send(ctx, msg)`
- `parseSlackChatID` で `channelID` と `threadTS` を分離する。
- `PostMessageContext` で本文投稿する。
- 以前の受信メッセージに紐づく `pendingAcks` があれば `white_check_mark` を付与する。

### `eventLoop()`
- `socketClient.Events` を継続購読する。
- `EventsAPI`, `SlashCommand`, `Interactive` を種別分岐する。

### `handleEventsAPI(event)`
- request ack 後に `slackevents.EventsAPIEvent` を取り出す。
- `MessageEvent` と `AppMentionEvent` をそれぞれ専用ハンドラへ渡す。

### `handleMessageEvent(ev)`
- 自 Bot、bot 投稿、非対応 subtype を除外する。
- allowlist 通過後、eyes リアクションを付けて `pendingAcks` に登録する。
- テキストから Bot mention を除去し、添付ファイルを取得する。
- スレッドなら `channel/thread_ts`、非スレッドなら `channel` を chatID とする。

### `handleAppMention(ev)`
- 明示的 mention イベントを処理する。
- スレッド中なら既存 threadTS、通常チャンネルなら messageTS を新規 thread ID とする。

### `handleSlashCommand(event)`
- request ack 後、空テキストなら `help` を本文とする。
- `is_command=true` を metadata に付けて `HandleMessage` へ渡す。

### 補助関数
- `downloadSlackFile`
- `stripBotMention`
- `parseSlackChatID`

## 詳細動作
### 起動
1. トークン妥当性を `AuthTest` で確認する。
2. `botUserID` を保持して、自分自身の投稿除外や mention 除去に使う。
3. Socket Mode のイベントループをバックグラウンドで動かす。

### 通常メッセージ受信
1. 投稿者が Bot または不明なら無視する。
2. subtype は空または `file_share` のみ許容する。
3. allowlist で拒否されたら以降のファイルダウンロードも行わない。
4. eyes リアクションを付与し、応答完了後にチェックを付けるため `pendingAcks` に記録する。
5. 添付ファイルは `Authorization: Bearer <BotToken>` 付きでダウンロードする。
6. Data URL 化できない添付は本文に `[audio: name]` と追記する。

### mention / slash command
- mention は常に 1 会話単位へ束ねるため、非スレッドでも `channel/messageTS` を chatID にする。
- slash command は Slack 側のコマンドテキストをそのまま本文として内部処理へ流す。

### 送信
- `chatID` に `/` が含まれれば thread reply として送信する。
- 応答後に `pendingAcks.LoadAndDelete` で完了印を付ける。

## 入出力・副作用・永続化
### 入力
- Socket Mode イベント
- Slack ファイルダウンロード URL
- `bus.OutboundMessage`

### 出力
- `MessageBus` への `InboundMessage`
- Slack への投稿、リアクション追加

### 副作用
- Slack API / Socket Mode 通信
- 一時ファイル作成・削除
- `pendingAcks` 更新
- ログ出力

### 永続化
- 永続化なし
- `pendingAcks` はメモリ保持のみ
- 添付ファイルは一時ファイルで、defer 削除

## 依存関係
- `github.com/slack-go/slack`
- `github.com/slack-go/slack/slackevents`
- `github.com/slack-go/slack/socketmode`
- `pkg/bus`, `pkg/config`, `pkg/logger`, `pkg/utils`
- `context`, `fmt`, `os`, `strings`, `sync`

## エラーハンドリング・制約
- 必須トークン欠如時は生成失敗。
- `AuthTest` や `PostMessageContext` の失敗は `error` を返す。
- イベントループ内の一部 API 失敗は戻り値化されず、継続動作する。
- `pendingAcks` への登録はメッセージ 1 件単位で、プロセス再起動で失われる。
- Slash command と EventsAPI の両方で `Ack` 呼び出しが必要な実装になっている。

