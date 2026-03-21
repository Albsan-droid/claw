# ランタイムフロー

## 1. gateway 起動フロー

出典の中心は `cmd/clawdroid/main.go` の `gatewayCmd()` です。

### 1.1 setup mode

```text
loadConfig()
  ↓
config.json 不在
  ↓
gatewaySetupMode()
  ├─ bus.NewMessageBus()
  ├─ gateway.NewServer().Start()
  ├─ channels.NewManager().StartAll()
  └─ setup wizard 完了 or SIGTERM 待機
```

このモードでは `AgentLoop` を作らないため、チャットは設定完了まで進みません。`pkg/channels/websocket.go` の `handleWS()` は `config.json` 不在時に `setup_required` を WebSocket で送ります。

### 1.2 degraded mode

```text
loadConfig()
  ↓
bus.NewMessageBus()
  ↓
gateway.NewServer().Start()
  ↓
channels.Manager.StartAll()
  ↓
providers.CreateProvider() 失敗
  ↓
固定エラーメッセージ返信 goroutine 起動
```

`msgBus.ConsumeInbound(ctx)` を読み、`OutboundMessage` に固定文を積むだけで、LLM もツールも動きません。

### 1.3 full mode

```text
loadConfig()
  ↓
bus.NewMessageBus()
  ↓
gateway.NewServer().Start()
  ↓
channels.Manager.StartAll()
  ↓
providers.CreateProvider()
  ↓
agent.NewAgentLoop()
  ↓
agentLoop.SetChannelManager()
  ↓
setupCronTool()
  ↓
heartbeat.NewHeartbeatService()
  ↓
heartbeatService.SetBus() / SetHandler()
  ↓
cronService.Start() / heartbeatService.Start()
  ↓
go agentLoop.Run(ctx)
```

## 2. 直接対話フロー (`agent` モード)

`cmd/clawdroid/main.go` の `agentCmd()` は `providers.CreateProvider()` と `agent.NewAgentLoop()` を作り、2 パターンで動きます。

- `-m/--message` 指定あり: `ProcessDirect(ctx, message, sessionKey)` を 1 回実行
- 指定なし: `interactiveMode()` または `simpleInteractiveMode()` で REPL 風に継続実行

直列フロー:

```text
CLI 入力
  ↓
AgentLoop.ProcessDirect()
  ↓
ProcessDirectWithChannel(..., "cli", "direct")
  ↓
processMessage()
  ↓
runAgentLoop()
```

## 3. inbound メッセージフロー

### 3.1 共通経路

各チャネルは最終的に `pkg/channels/base.go` の `BaseChannel.HandleMessage()` を呼び、`bus.InboundMessage` を生成して `MessageBus.PublishInbound()` に渡します。

主要フィールド:

- `Channel`
- `SenderID`
- `ChatID`
- `Content`
- `Media`
- `SessionKey`
- `Metadata`

### 3.2 WebSocket から AgentLoop まで

```text
Android / WebSocket client
  ↓
WebSocketChannel.handleWS()
  ↓
go readPump(conn, clientID, chatID, clientType, locale)
  ↓
wsIncoming を JSON decode
  ├─ Type == "tool_response"
  │    → tools.DeviceResponseWaiter.Deliver()
  └─ それ以外
       → BaseChannel.HandleMessage()
       → MessageBus.PublishInbound()
       → AgentLoop.Run()
```

出典:

- `pkg/channels/websocket.go` の `wsIncoming`, `handleWS()`, `readPump()`
- `pkg/channels/base.go` の `HandleMessage()`
- `pkg/agent/loop.go` の `Run()`

### 3.3 AgentLoop 内での受信処理

`pkg/agent/loop.go` の `processMessage()` は次を行います。

1. locale / input_mode を `Metadata` から抽出
2. `rateLimiter.checkRequest()` を実行
3. `/show`, `/list`, `/switch` などのコマンド処理
4. `UserStore.ResolveByChannelID()` でユーザー解決
5. `runAgentLoop(processOptions{...})` へ委譲

## 4. runAgentLoop の主フロー

`pkg/agent/loop.go` の `runAgentLoop()` が会話処理の本体です。

```text
runAgentLoop()
  1. state.Manager に `channel:chatID` 形式の最終チャネルを記録し、`ChannelChatIDs[channel]=chatID` も更新
  2. updateToolContexts()
  3. sessions/history/summary を読み出し
  4. ContextBuilder.BuildMessages()
  5. ユーザーメッセージと media を session に保存
  6. "thinking" status を outbound 送信
  7. runLLMIteration()
  8. 応答を session 保存
  9. maybeSummarize()
 10. 必要なら outbound 送信
```

補助状態送信:

- 開始時: `type: "status"`
- 終了時: `AgentLoop.Run()` の defer で `type: "status_end"`
- 10 秒ごと: heartbeat ticker が現在 status を再送

## 5. LLM + ツール実行フロー

`runLLMIteration()` は `providers.LLMProvider.Chat()` を呼び、`response.ToolCalls` がある限りループします。

### 5.1 反復処理

```text
AgentLoop.runLLMIteration()
  ↓
ToolRegistry.ToProviderDefs()
  ↓
provider.Chat(ctx, messages, toolDefs, model, llmOpts)
  ↓
ToolCalls あり?
  ├─ なし → finalContent で終了
  └─ あり → 各 tool call を実行
```

### 5.2 ツール呼び出し

各ツール呼び出しでは以下を行います。

1. `rateLimiter.checkToolCall()`
2. `statusLabel(...)` による状態表示更新
3. `ToolRegistry.ExecuteWithContext()`
4. `ToolResult.ForUser` を必要時ユーザーへ即時送信
5. `ToolResult.ForLLM` と `ToolCallID` を `providers.Message{Role:"tool"}` として会話へ追加
6. session に保存

出典:

- `pkg/agent/loop.go` の `runLLMIteration()`
- `pkg/tools/registry.go` の `ExecuteWithContext()`
- `pkg/tools/result.go` の `ToolResult`

### 5.3 非同期ツール

Async 対応は `pkg/tools/base.go` の `AsyncTool` / `AsyncCallback` で表現されます。`ToolRegistry.ExecuteWithContext()` は `SetCallback()` を注入できます。

現行実装で代表的なのは subagent 系です。

- `pkg/tools/subagent.go` の `SubagentManager.Spawn()`
- `pkg/tools/spawn.go`（登録は `pkg/agent/loop.go` の `createToolRegistry()` 後）

## 6. Android ツール往復フロー

`pkg/tools/android.go` と `pkg/channels/websocket.go` の組み合わせで device action が往復します。

```text
LLM が android tool を要求
  ↓
AndroidTool.Execute()
  ↓
AndroidTool.sendAndWait()
  ├─ request_id を発行
  ├─ DeviceResponseWaiter.Register(request_id)
  ├─ sendCallback(..., msgType="tool_request")
  └─ response / timeout / cancel を待機

Android 側
  ↓
"tool_response" を WebSocket 送信
  ↓
WebSocketChannel.readPump()
  ↓
DeviceResponseWaiter.Deliver(request_id, content)
  ↓
AndroidTool.sendAndWait() が復帰
```

補足:

- `screenshot` は base64 JPEG を `ToolResult.Media` に格納
- `accessibility_required...` で始まる応答は、ユーザー向け日本語メッセージと LLM 向け説明を分けて返す
- タイムアウトは 15 秒 (`androidToolTimeout`)

## 7. outbound 配信フロー

```text
AgentLoop / Heartbeat / degraded-mode goroutine
  ↓
MessageBus.PublishOutbound()
  ↓
channels.Manager.dispatchOutbound()
  ↓
対象 Channel.Send(ctx, msg)
```

重要な分岐:

- `pkg/constants/channels.go` の内部チャネルは配送しない
- `type == "status"` は `websocket` 専用
- WebSocket 接続が無く `client_type == "main"` なら `maybeBroadcast()` を試す

## 8. Cron 実行フロー

### 8.1 登録

`cmd/clawdroid/main.go` の `setupCronTool()` が次を行います。

- `cron.NewCronService(cronStorePath, nil)`
- `tools.NewCronTool(...)`
- `agentLoop.RegisterTool(cronTool)`
- `cronService.SetOnJob(...)`

### 8.2 実行

```text
CronService.runLoop()
  ↓
checkJobs()
  ↓
executeJobByID(jobID)
  ↓
onJob(callbackJob)
  ↓
CronTool.ExecuteJob(...)
  ↓
AgentLoop.ProcessDirectWithChannel(...)
```

出典:

- `pkg/cron/service.go`
- `pkg/tools/cron.go`
- `cmd/clawdroid/main.go` の `setupCronTool()`

## 9. Heartbeat フロー

`pkg/heartbeat/service.go` の `HeartbeatService` は定期的に `HEARTBEAT.md` を読み、最後のメインチャネルへ通知対象を解決します。

```text
HeartbeatService.runLoop()
  ↓
executeHeartbeat()
  ↓
buildPrompt()  // {dataDir}/HEARTBEAT.md
  ↓
state.GetLastMainChannel() / GetLastChannel()
  ↓
handler(prompt, channel, chatID)
  ↓
agentLoop.ProcessHeartbeat()
```

特性:

- heartbeat は `NoHistory: true` で既存履歴をロードせずに処理する
- ただし `SessionKey` は固定で `heartbeat` であり、リクエスト/応答自体は通常どおり session に保存される
- `ProcessHeartbeat()` は `SendResponse: false` で実行される
- 既定の `heartbeatService.SetHandler()` は非エラー応答を `HEARTBEAT_OK` を含めてすべて `SilentResult(...)` に包むため、通常の gateway 配線では heartbeat の非エラー結果はユーザーチャネルへ送られない
- `HEARTBEAT.md` が無ければテンプレートを生成して今回実行はスキップ

## 10. 設定更新と再起動フロー

`pkg/gateway/handlers.go` の `handlePutConfig()` と `pkg/gateway/setup.go` の `handleSetupComplete()` は、いずれも設定保存後に `onRestart()` を遅延実行しますが、レスポンス JSON の形は一致しません。

```text
HTTP PUT /api/config
  ↓
config.SaveConfigLocked()
  ↓
s.cfg.CopyFrom(&newCfg)
  ↓
JSON {status:"ok", restart:true}
  ↓
go onRestart()
  ↓
gatewayCmd() の restartCh 受信
  ↓
shutdown → execRestart()
```

```text
HTTP PUT /api/setup/complete
  ↓
config.SaveConfigLocked()
  ↓
s.cfg.CopyFrom(&newCfg)
  ↓
JSON {status:"ok"}
  ↓
go onRestart()
  ↓
gatewayCmd() の restartCh 受信
  ↓
shutdown → execRestart()
```

Go 側は「設定保存」と「再起動要求通知」を一貫して backend で処理しています。
