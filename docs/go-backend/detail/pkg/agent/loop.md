# pkg/agent/loop.go

## 対象ソース
- `pkg/agent/loop.go`

## 概要
`AgentLoop` は、メッセージバスから受信した入力を LLM とツール実行に接続する中核コンポーネントである。セッション履歴、状態保存、ユーザー解決、ツールのコンテキスト注入、コンテキスト圧縮、要約生成、レート制限、サブエージェント連携を 1 つのループに統合している。

## 責務
- ツール群・状態管理・セッション管理・サブエージェントの初期化
- 受信メッセージごとの並行処理制御（キュー / キャンセル）
- システムメッセージと通常メッセージの振り分け
- LLM 反復呼び出しとツールコール実行
- ステータス表示、警告表示、応答送信
- 会話履歴の要約・圧縮・メディアファイル掃除
- `/show`, `/list`, `/switch` コマンド処理

## 主要な型・関数・メソッド
### 型
- `AgentLoop`
  - `bus`: `*bus.MessageBus`
  - `provider`: `providers.LLMProvider`
  - `sessions`: `*session.SessionManager`
  - `state`: `*state.Manager`
  - `contextBuilder`: `*ContextBuilder`
  - `tools`: `*tools.ToolRegistry`
  - `userStore`: `*UserStore`
  - `rateLimiter`: `*rateLimiter`
  - `mcpManager`: `*mcp.Manager`
  - `activeProcs`: セッションキーごとの実行中プロセス
  - `mediaDir`: 永続メディア保存先
  - `queueMessages`, `showErrors`, `showWarnings`: 実行ポリシー
- `activeProcess`
  - `cancel`, `done`
- `processOptions`
  - `SessionKey`, `Channel`, `ChatID`, `UserMessage`, `Media`
  - `DefaultResponse`, `EnableSummary`, `SendResponse`, `NoHistory`
  - `InputMode`, `Metadata`, `ResolvedUser`, `Locale`

### 主要関数・メソッド
- `createToolRegistry(...) *tools.ToolRegistry`
- `NewAgentLoop(cfg, msgBus, provider) *AgentLoop`
- `Run(ctx context.Context) error`
- `Stop()`
- `ProcessDirect(...)`, `ProcessDirectWithChannel(...)`
- `ProcessHeartbeat(...)`
- `processMessage(...)`
- `processSystemMessage(...)`
- `runAgentLoop(...)`
- `runLLMIteration(...)`
- `updateToolContexts(...)`
- `maybeSummarize(...)`
- `forceCompression(...)`
- `summarizeSession(...)`
- `summarizeBatch(...)`
- `estimateTokens(...)`
- `handleCommand(...)`
- 補助: `GetStartupInfo`, `formatMessagesForLog`, `formatToolsForLog`

## 詳細動作
### ツールレジストリ生成 (`createToolRegistry`)
- 常に登録するもの
  - `read_file`, `write_file`, `list_dir`, `edit_file`, `append_file`
  - `copy_file`（`dataDir/media` から workspace へのコピーを許可）
  - `web_fetch`
  - `message`
- 設定で有効なときだけ登録するもの
  - `exec`
  - `android`
  - `web_search`（`NewWebSearchTool(...)` が `nil` でない場合）
- `message` と `android` は `MessageBus.PublishOutbound` を使うコールバックを埋め込む。

### 初期化 (`NewAgentLoop`)
- `workspace` と `dataDir` を作成する。
- `dataDir/media` を作り、ツール結果やユーザー入力画像を永続化する保存先にする。
- メイン用とサブエージェント用で別々の `ToolRegistry` を作る。
- サブエージェントには `spawn` / `subagent` を入れず、再帰呼び出しを避ける。
- メイン側のみ `spawn`, `exit`, `subagent` を追加する。
- セッションは `dataDir/sessions`、状態は `state.NewManager(dataDir)` で `dataDir/state/state.json` を使う。
- `message` ツールへ `stateManager` を注入し、`app` エイリアスやクロスチャネル送信で利用する。
- `UserStore` を生成し、`user` ツールへ接続する。
- memory ツールは設定有効時のみ登録し、`ContextBuilder` にも有効フラグを渡す。
- スキルツールは常時登録する。
- MCP 設定があるときは `mcp.Manager` と bridge tool を作り、`ContextBuilder` にも設定する。

### 受信ループ (`Run`)
- `bus.ConsumeInbound(ctx)` で入力を取り出す。
- `SessionKey` が空なら `<channel>:<chatID>` から生成する。
- 同じ `sessionKey` の処理が実行中なら以下のどちらかを行う。
  - `queueMessages=true`: 完了待ち
  - `queueMessages=false`: 既存処理を `cancel()` し、最大 5 秒待ってから置換
- 各入力は goroutine で `processMessage` へ渡す。
- 完了時は必ず `status_end` を発行し、`activeProcs` から自分自身を削除する。
- `processMessage` が応答文字列を返した場合のみ最終応答を outbound へ流す。

### メッセージ前処理 (`processMessage`)
- ログ用の本文は通常 80 文字まで `utils.Truncate` し、`Error:` を含む場合は全文を使う。
- `channel == "system"` のときは `processSystemMessage` に分岐する。
- `Metadata` から `input_mode` と `locale` を読み、`locale` は `i18n.NormalizeLocale` する。
- `rateLimiter.checkRequest()` に失敗した場合は翻訳済みメッセージを返して処理終了する。
- `/show`, `/list`, `/switch` は `handleCommand` で処理する。
- 初回入力時のみ、`USER.md` からの移行が必要なら migration notice を 1 回送る。
- `userStore.ResolveByChannelID` に成功した場合は入力を `[Name]: ...` に書き換える。
- 未解決かつ WebSocket 以外のときは `[channel:senderID]: ...` を前置する。

### システムメッセージ (`processSystemMessage`)
- `chat_id` 先頭の `channel:` 部分を origin channel とみなす。
- `"Result:\n"` があればそれ以降を抽出する。
- 内部チャネルの結果はログだけ出して捨てる。
- 外部チャネルでも、実装上は「サブエージェントが `message` ツールで直接通知する」前提のため、ここでは転送せずログのみ行う。

### コア処理 (`runAgentLoop`)
1. 外部チャネルなら `state.Manager` に `channel:chatID` 形式の最終チャネルを記録し、`SetChannelChatID(channel, chatID)` でチャネル別 chatID マップも更新する。`SetLastChatID()` はこの経路では呼ばれない。
2. `updateToolContexts` で `message`, `spawn`, `subagent`, `android`, `exit` にチャネル情報を渡す。
3. `NoHistory=false` のときだけセッション履歴とサマリーをロードする。`ProcessHeartbeat()` のように `NoHistory=true` でも、現在の入出力メッセージ自体は固定 `SessionKey="heartbeat"` の session に保存される。
4. `ContextBuilder.BuildMessages` で LLM 入力配列を組み立てる。
5. 現在のユーザーメッセージは必ずセッションに保存する。`Media` がある場合は `PersistMedia` で `dataDir/media` に保存し、本文へ `[Image: <path>]` を追記してから保存する。
6. 外部チャネルなら `status.thinking` を送信し、10 秒ごとの heartbeat 再送 goroutine を開始する。
7. `runLLMIteration` を呼ぶ。
8. キャンセル時は、`queueMessages=false` の場合に限り `status.interrupted` を assistant メッセージとして保存し、ユーザーへの返信は返さない。
9. `NO_REPLY` なら `[silent]` を履歴へ保存し、応答は返さない。
10. 空応答なら `DefaultResponse` に置き換える。
11. 最終 assistant 応答をセッションへ保存し、必要なら `maybeSummarize` を起動する。
12. `SendResponse=true` の場合だけここでも outbound へ送る。通常の `processMessage` 経路では `SendResponse=false` なので、呼び出し元 goroutine が戻り値を送信する。

### LLM 反復処理 (`runLLMIteration`)
- 最大 `maxIterations` 回ループする。
- 毎回 `ToolRegistry.ToProviderDefs()` からツール定義を作る。
- 詳細ログとしてメッセージとツール定義の整形済みダンプを残す。
- `provider.Chat` は最大 2 回までリトライする。
  - `token`, `context`, `invalidparameter`, `length` を含むエラーはコンテキスト超過扱い
  - 初回リトライ時のみ warning をユーザーへ出す（`SendResponse` と `showWarnings` が真の場合）
  - `forceCompression(sessionKey)` 実行後、セッション履歴からメッセージ列を再構築して再試行する
- ツール呼び出しが無ければ `response.Content` を最終応答にして終了する。
- ツール呼び出しがある場合
  - assistant メッセージに `ToolCalls` を組み立てて `messages` と session に保存
  - 各ツールコールごとに `checkToolCall()` を実行
  - レート超過時は翻訳済みエラー文を `role=tool` で返し、ループを継続
  - `statusLabel` が生成できれば外部チャネルへ status として送信し、heartbeat 用 `currentStatus` も更新
  - `tools.ExecuteWithContext(...)` を呼び、必要なら `ForUser` を即時送信する（`SendResponse=true` の場合のみ）
  - `ForLLM` が空かつ `Err != nil` ならエラー文字列を LLM 向け本文に使う
  - `toolResult.Media` があれば `PersistMedia` して `[Image: ...]` を追記する
  - 最終的に `role=tool` メッセージとして `messages` と session に保存する

### 要約と圧縮
#### `maybeSummarize`
- 履歴件数が 20 件超、または推定トークン数が `contextWindow * 75%` を超えると非同期要約を起動する。
- 同じ `sessionKey` の重複要約は `sync.Map` で抑止する。

#### `summarizeSession`
- タイムアウト 120 秒の独立 `context.Background()` を使う。
- 直近 4 メッセージは残し、それ以前を要約対象にする。
- 対象から `user` / `assistant` 以外を除外する。
- 個々のメッセージが `contextWindow/2` トークン相当を超える場合は丸ごと除外する。
- 有効メッセージが 10 件超なら 2 分割要約し、その結果をさらに LLM でマージする。
- 要約成功時は、要約対象から `CleanupMediaFiles` でメディアを掃除し、`Session.Summary` を更新して履歴を直近 4 件へ切り詰める。

#### `forceCompression`
- 実装は session 履歴に対して動作し、コメントにある「system prompt」ではなく **履歴先頭メッセージ `history[0]`** を保持する。
- `history[1:len(history)-1]` を会話本体として半分まで落とし、tool call / tool response の途中で切れないよう `mid` を前進させる。
- 破棄範囲のメディアは `CleanupMediaFiles` で削除する。
- 先頭メッセージ + 圧縮ノート（`role=user`）+ 残した後半 + 最終メッセージ、という新履歴に置き換える。

### ツールコンテキスト更新 (`updateToolContexts`)
- `message`, `spawn`, `subagent`, `android` は `tools.ContextualTool.SetContext(channel, chatID)` を呼ぶ。
- `android` は `metadata["client_type"]` も `SetClientType` へ渡す。
- `exit` はチャネル / chatID に加え `metadata["input_mode"]` を `SetInputMode` へ渡す。

### コマンド (`handleCommand`)
- `/show model|channel`
- `/list models|channels`
- `/switch model to <value>`
- `/switch channel to <value>`
- `channel` 切替は `channelManager` の存在確認と対象チャネルの存在確認を行うが、`al.model` 書き換え以外に永続化はしない。

## 入出力・副作用・永続化
### 入力
- `bus.InboundMessage`
- LLM からの `providers.LLMResponse`
- `config.Config`
- `Metadata` 中の `input_mode`, `locale`, `client_type`

### 出力
- 最終応答文字列
- `bus.OutboundMessage`（status / warning / error / 通常返信）
- `GetStartupInfo()` による起動情報マップ

### 副作用
- `dataDir/sessions/*.json` への会話保存
- `dataDir/state/state.json` への状態保存
- `dataDir/media/*` への画像保存と不要画像削除
- `MessageBus.PublishOutbound` による通知送信
- `logger.InfoCF/DebugCF/WarnCF/ErrorCF` による詳細ログ
- goroutine 起動（受信処理、heartbeat、要約）

### 永続化
- セッション履歴: `SessionManager`
- 最後に使ったチャネル文字列とチャネル別 chatID マップ: `state.Manager`
- メディアファイル: `PersistMedia` で `dataDir/media`

## 依存関係
- `pkg/bus`
- `pkg/channels`
- `pkg/config`
- `pkg/constants`
- `pkg/i18n`
- `pkg/logger`
- `pkg/mcp`
- `pkg/providers`
- `pkg/session`
- `pkg/state`
- `pkg/tools`
- `pkg/utils`
- 同一パッケージ内の `ContextBuilder`, `UserStore`, `PersistMedia`, `CleanupMediaFiles`, `statusLabel`, `rateLimiter`
- 標準ライブラリ: `context`, `encoding/json`, `fmt`, `os`, `path/filepath`, `strings`, `sync`, `sync/atomic`, `time`, `unicode/utf8`

## エラーハンドリング・制約
- リクエスト / ツールのレート超過はエラーではなくユーザー向けメッセージへ変換される場合がある。
- `Run` 中の処理キャンセルは、`queueMessages=false` のとき新着メッセージにより発生しうる。
- コンテキスト超過判定は文字列包含ベースであり、プロバイダ固有コードの厳密判定ではない。
- `provider.Chat` が返す `model` 引数の切替は `al.model` に依存するが、実際にアダプタがその引数を尊重するかは `providers` 実装次第。
- `ProcessHeartbeat` は既存履歴をロードせず、`SessionKey` を固定で `heartbeat` にする。ただし現在のリクエスト/応答はこの session に保存され続ける。
- `forceCompression` / `summarizeSession` はセッション内容を破壊的に変更するため、再構築不能な詳細（削除済みメディアを含む）は失われる。
