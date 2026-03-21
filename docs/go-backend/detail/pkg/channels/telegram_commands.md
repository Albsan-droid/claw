# telegram_commands.go 詳細設計

## 対象ソース
- `pkg/channels/telegram_commands.go`

## 概要
Telegram 向けのスラッシュコマンド実装をまとめた補助ファイル。`help` / `start` / `show` / `list` をローカライズ付きで返答する。

## 責務
- Telegram コマンド処理インターフェース定義
- 具体コマンド実装の提供
- 引数抽出とロケール解決
- 現在設定値に基づくメッセージ組み立て

## 主要な型・関数・メソッド
### `type TelegramCommander interface`
- `Help(ctx, message) error`
- `Start(ctx, message) error`
- `Show(ctx, message) error`
- `List(ctx, message) error`

### `type cmd struct`
- `bot *telego.Bot`
- `config *config.Config`

### `NewTelegramCommands(bot, cfg) TelegramCommander`
- `cmd` を返すファクトリ。

### `commandArgs(text string) string`
- 最初の空白で 2 分割し、コマンド以降の引数文字列を返す。
- 引数がなければ空文字。

### `(*cmd) Help`
- `i18n.T(locale, "cmd.help")` を返信する。

### `(*cmd) Start`
- `i18n.T(locale, "cmd.start")` を返信する。

### `(*cmd) Show`
- 引数なしなら usage を返す。
- `show model` は `config.LLM.Model` を表示する。
- `show channel` は固定文言 `cmd.show.channel` を返す。
- その他は unknown 応答。

### `(*cmd) List`
- 引数なしなら usage を返す。
- `list models` は現在モデル名を埋め込んだ文言を返す。
- `list channels` は有効フラグを見て `telegram/whatsapp/discord/slack/line` を列挙する。
- その他は unknown 応答。

### `localeFromMessage(message telego.Message) string`
- `message.From.LanguageCode` を `i18n.NormalizeLocale` に通す。
- 送信者不明時は `"en"`。

## 詳細動作
- すべてのコマンド応答は `ReplyParameters.MessageID` を指定し、元メッセージへの返信として送る。
- `Show` / `List` は毎回 `config` の現在値を参照して応答文を組み立てる。
- `list channels` では WebSocket は列挙対象に含まれていない。ソース上で判定しているのは Telegram / WhatsApp / Discord / Slack / LINE のみである。

## 入出力・副作用・永続化
### 入力
- Telegram の `telego.Message`
- `config.Config`

### 出力
- Telegram への返信メッセージ送信
- 成功時 `nil`、失敗時 `bot.SendMessage` の `error`

### 副作用
- 外部 API として Telegram Bot API を呼ぶ

### 永続化
- なし

## 依存関係
- `context`
- `strings`
- `github.com/KarakuriAgent/clawdroid/pkg/config`
- `github.com/KarakuriAgent/clawdroid/pkg/i18n`
- `github.com/mymmrac/telego`

## エラーハンドリング・制約
- コマンド引数の厳密バリデーションは行わず、未知値は unknown 文言にフォールバックする。
- 返信送信失敗はそのまま `error` を返す。
- `list channels` の出力対象はハードコードされており、Manager に登録済みチャネル一覧を動的取得していない。

