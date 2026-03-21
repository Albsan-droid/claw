# アーキテクチャ概要

## 1. エントリポイントとプロセスモード

Go バックエンドの単一エントリポイントは `cmd/clawdroid/main.go` の `main()` です。`os.Args[1]` でサブコマンドを切り替えます。

| モード | 起点シンボル | 役割 |
| --- | --- | --- |
| `onboard` | `onboard()` | `~/.clawdroid/config.json` の初期生成とテンプレート展開 |
| `agent` | `agentCmd()` | 直接対話用の CLI 実行 |
| `gateway` | `gatewayCmd()` | 常駐サーバー本体。HTTP Config API・チャネル・AgentLoop を起動 |
| `status` | `statusCmd()` | 現在の設定/作業ディレクトリの確認 |
| `cron` | `cronCmd()` | Cron ジョブ管理 CLI |
| `skills` | `skills*Cmd()` 群 | Skill 一覧/表示/削除/builtin 一覧/builtin 導入 |
| `version` | `printVersion()` | バージョン表示 |

出典: `cmd/clawdroid/main.go`

## 2. gateway 実行時のランタイムモード

`gatewayCmd()` は同じ `gateway` サブコマンドの中で 3 つの実行状態を持ちます。

### setup mode

`config.json` が存在しない場合、`gatewaySetupMode()` に分岐します。

- `gateway.NewServer()` による HTTP API 起動
- `channels.NewManager()` と `StartAll()` によるチャネル起動
- **LLM Provider / AgentLoop / Cron / Heartbeat は起動しない**

出典: `cmd/clawdroid/main.go` の `gatewayCmd()`, `gatewaySetupMode()`

### degraded mode

設定ファイルはあるが `providers.CreateProvider()` が失敗した場合のモードです。

- HTTP Config API は稼働
- チャネルも稼働
- AgentLoop は作らない
- `msgBus.ConsumeInbound()` を読む goroutine が固定メッセージを返す

出典: `cmd/clawdroid/main.go` の `gatewayCmd()`、`pkg/providers/provider.go` の `CreateProvider()`

### full mode

通常運用モードです。

- `gateway.Server`
- `channels.Manager`
- `agent.AgentLoop`
- `cron.CronService`
- `heartbeat.HeartbeatService`

をまとめて起動します。

## 3. ランタイムを構成する主要コンポーネント

### 3.1 AgentLoop

中核は `pkg/agent/loop.go` の `type AgentLoop struct` と `Run()` です。

主要フィールド:

- `bus *bus.MessageBus`
- `provider providers.LLMProvider`
- `sessions *session.SessionManager`
- `state *state.Manager`
- `tools *tools.ToolRegistry`
- `contextBuilder *ContextBuilder`
- `userStore *UserStore`
- `mcpManager *mcp.Manager`
- `activeProcs map[string]*activeProcess`

役割:

1. inbound メッセージを受信
2. セッション単位で並行実行を制御
3. プロンプト構築
4. LLM 呼び出し
5. ツール呼び出しループ
6. 結果保存と outbound 配信

### 3.2 MessageBus

`pkg/bus/bus.go` の `MessageBus` は in-memory のメッセージ中継器です。

- `PublishInbound()` / `ConsumeInbound()`
- `PublishOutbound()` / `SubscribeOutbound()`

チャネル実装と AgentLoop の間を疎結合にしています。

### 3.3 Channel Manager

`pkg/channels/manager.go` の `Manager` が利用可能チャネルを初期化・起動・停止します。

現在の実装対象:

- `telegram`
- `whatsapp`
- `discord`
- `slack`
- `line`
- `websocket`

`StartAll()` は各チャネル起動に加え、`dispatchOutbound()` goroutine を開始して outbound を各チャネルの `Send()` へ配送します。

### 3.4 Gateway Server

`pkg/gateway/server.go` の `Server` は `127.0.0.1:<port>` に HTTP サーバーを立て、設定 API とセットアップ API を提供します。

主なハンドラ:

- `handleGetSchema()`
- `handleGetConfig()`
- `handlePutConfig()`
- `handleSetupInit()`
- `handleSetupComplete()`

### 3.5 補助常駐サービス

- `pkg/cron/service.go` の `CronService`
- `pkg/heartbeat/service.go` の `HeartbeatService`
- `pkg/mcp/manager.go` の `Manager`（MCP サーバープロセス管理、idle reaper あり）

## 4. 起動シーケンス

### full mode の順序

`cmd/clawdroid/main.go` の `gatewayCmd()` では概ね次の順で進みます。

1. `loadConfig()` で `config.LoadConfig()` 実行
2. `bus.NewMessageBus()`
3. `gateway.NewServer(...).Start()`
4. `channels.NewManager(...).StartAll(ctx)`
5. `providers.CreateProvider(cfg)`
6. `agent.NewAgentLoop(cfg, msgBus, provider)`
7. `agentLoop.SetChannelManager(channelManager)`
8. `setupCronTool(...)` で `CronTool` 登録と `CronService` 連携
9. `heartbeat.NewHeartbeatService(...)`
10. `heartbeatService.SetBus(msgBus)` / `heartbeatService.SetHandler(...)`
11. `cronService.Start()` / `heartbeatService.Start()`
12. `go agentLoop.Run(ctx)`

ポイント:

- Config API は LLM 不備時でも使えるよう **先に起動** します。
- `AgentLoop` は `provider` が作れたときだけ起動します。
- `CronService` と `HeartbeatService` は AgentLoop 作成後に初期化され、`agentLoop.Run(ctx)` より前に起動されます。

## 5. 停止シーケンス

`gatewayCmd()` は `os.Interrupt` / `SIGTERM`、または Config 更新による `restartCh` を待ちます。

停止順:

1. `cancel()` で共有 context を停止
2. `gwServer.Stop(shutdownCtx)`
3. `heartbeatService.Stop()`
4. `cronService.Stop()`
5. `agentLoop.Stop()`
6. `channelManager.StopAll(shutdownCtx)`
7. `execRestart()`（必要時のみ）

出典: `cmd/clawdroid/main.go` の `gatewayCmd()`

## 6. Android 統合の接点

### 6.1 WebSocket チャネル

Android アプリとの主経路は `pkg/channels/websocket.go` の `WebSocketChannel` です。

- `handleWS()` が接続を受理
- `readPump()` が受信ループ
- `Send()` が Go → Android 送信

クエリパラメータ:

- `api_key`
- `client_id`
- `client_type`
- `locale`

### 6.2 Android ツールブリッジ

`pkg/tools/android.go` の `AndroidTool` は device action を `tool_request` として WebSocket 送信し、`ResponseWaiter` で `tool_response` を待ちます。

関連シンボル:

- `toolRequest`
- `AndroidTool.sendAndWait()`
- `tools.DeviceResponseWaiter`
- `WebSocketChannel.readPump()`

### 6.3 broadcast フォールバック

`pkg/channels/websocket.go` の `maybeBroadcast()` は、`client_type == "main"` の WebSocket 接続が切れているとき、`pkg/broadcast/broadcast.go` の `broadcast.Send()` を使って Android に `am broadcast` を送ります。

Intent 定数:

- `broadcast.Action = "io.clawdroid.AGENT_MESSAGE"`
- `broadcast.Package = "io.clawdroid"`

### 6.4 Android 向け実行環境調整

`cmd/clawdroid/main.go` の 2 つ目の `init()` は条件分岐なしで以下を設定します。コメント上の意図は Android APK など CGO 無効の pure-Go 実行時向けの補正ですが、DNS 差し替え自体は常に設定されます。

- `net.DefaultResolver.Dial` を `8.8.8.8:53` に向ける
- `SSL_CERT_DIR=/system/etc/security/cacerts` を必要時設定

CA 証明書パスの補正は Android 端末のパス存在時だけ効きます。DNS の差し替え自体は非 Android 環境を含めて常に設定されますが、コメントどおり CGO 有効ビルドでは通常 cgo resolver が使われるため、この `Dial` フックが実際に参照されないことがあります。

## 7. セッション処理モデル

`AgentLoop.Run()` は `sessionKey` ごとに `activeProcs` を持ちます。

- `cfg.Agents.Defaults.QueueMessages == true` のとき: 既存処理終了を待つ
- `false` のとき: 既存処理を `cancel()` して置き換える

出典:

- 設定値: `pkg/config/config.go` の `AgentDefaults.QueueMessages`
- 実行制御: `pkg/agent/loop.go` の `Run()`

## 8. 生成される内部コンテキスト

`pkg/agent/context.go` の `ContextBuilder` は次を組み合わせて system prompt を組み立てます。

- 実行時刻・ワークスペース・利用可能ツール
- Safety / Tool Call Style
- Sub-agent, Messaging, Cron, Memory, User 管理のガイダンス
- `AGENT.md`, `SOUL.md`, `IDENTITY.md`（存在時）
- Skill 一覧と Skill 本文
- MCP サーバー概要

つまり AgentLoop は単純な LLM 呼び出しではなく、Go 側でかなり多くの実行文脈を注入する構成です。
