# pkg/tools/cron.go 詳細設計

## 対象ソース
- `pkg/tools/cron.go`

## 概要
会話中に指定されたリマインダー・定期実行・ cron 式ジョブを `pkg/cron` サービスへ登録し、発火時には直接配信・エージェント処理・シェル実行のいずれかへ橋渡しするスケジューリングツールである。

## 責務
- ジョブの追加・一覧・削除・有効化・無効化を提供する。
- セッション文脈（channel/chatID）をジョブ payload に保存する。
- `deliver` フラグに応じて直接配信かエージェント処理かを切り替える。
- `execEnabled` 時のみスケジュール実行時のシェルコマンドを許可する。

## 主要な型・関数・メソッド
### `type JobExecutor interface`
- `ProcessDirectWithChannel(ctx, content, sessionKey, channel, chatID string) (string, error)`

### `type CronTool struct`
- 主なフィールド: `cronService`, `executor`, `msgBus`, `execTool`, `execEnabled`, `channel`, `chatID`, `mu`
- `NewCronTool(cronService, executor, msgBus, workspace, restrict, execEnabled)`
- `SetContext(channel, chatID string)`
- `Execute(ctx, args) *ToolResult`
- `ExecuteJob(ctx, job *cron.CronJob) string`

### 内部メソッド
- `addJob(args)`
- `listJobs()`
- `removeJob(args)`
- `enableJob(args, enable bool)`

## 詳細動作
### ツール呼び出し時
- `action` に応じて `add/list/remove/enable/disable` を分岐する。
- `add` ではスケジュール種別を優先順 `at_seconds > every_seconds > cron_expr` で解釈する。
- `at_seconds`, `every_seconds` は JSON 数値として受けるため Go 側では `float64` から変換される。
- `deliver` は未指定時 true。`command` が指定されると `deliver` は強制的に false へ変更される。
- ジョブ名には `utils.Truncate(message, 30)` で短縮したプレビューを使う。
- `command` がある場合、`AddJob` 後に `job.Payload.Command` を更新し `cronService.UpdateJob(job)` を呼び直す。

### ジョブ発火時 (`ExecuteJob`)
1. payload から `channel` / `chatID` を取得し、欠けていれば `cli` / `direct` を補う。
2. `Command` があり `execTool != nil` なら `ExecTool.Execute` を呼び、結果を `MessageBus.PublishOutbound` で直接通知する。
3. `Deliver=true` なら payload の `Message` をそのまま outbound 送信する。
4. それ以外は `executor.ProcessDirectWithChannel` にメッセージを渡し、エージェントループへ処理を委譲する。

## 入出力・副作用・永続化
- 入力: スケジュール条件、メッセージ、ジョブ ID、`deliver`、任意の `command`、会話文脈。
- 出力: 無言成功結果、一覧文字列、またはエラー。
- 副作用: `cronService` へのジョブ登録/更新/削除、`MessageBus` への送信、任意のシェル実行。
- 永続化: ジョブの永続化実装自体は `pkg/cron.CronService` 側に委譲される。

## 依存関係
- 標準ライブラリ: `context`, `fmt`, `sync`, `time`
- 同一パッケージ: `ExecTool`, `SilentResult`, `ErrorResult`
- 他パッケージ: `pkg/bus`, `pkg/cron`, `pkg/utils`

## エラーハンドリング・制約
- `add` はアクティブ会話文脈が無いと失敗する。
- `message`、`job_id`、スケジュール指定など必須項目が欠けると即エラー。
- `execEnabled=false` の場合、`command` 引数は受け取っても無視される。
- `listJobs` は結果を `SilentResult` で返すため、呼び出し側が明示的にユーザーへ見せる必要がある。
