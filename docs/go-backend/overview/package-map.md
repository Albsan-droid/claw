# パッケージマップ

## 1. エントリポイント

## `cmd/clawdroid`

- 主ファイル: `cmd/clawdroid/main.go`
- 主シンボル: `main()`, `agentCmd()`, `gatewayCmd()`, `gatewaySetupMode()`, `setupCronTool()`, `getConfigPath()`
- 役割: サブコマンド分岐、Config 読み込み、Gateway 起動、CLI 対話、Cron/Skills 補助 CLI

## 2. 中核実行系

| パッケージ | 主ファイル / シンボル | 役割 |
| --- | --- | --- |
| `pkg/agent` | `loop.go` / `AgentLoop`, `Run`, `runAgentLoop`, `runLLMIteration` | メッセージ処理、LLM 呼び出し、ツールループ、履歴圧縮 |
| `pkg/agent` | `context.go` / `ContextBuilder` | system prompt と実行文脈の組み立て |
| `pkg/agent` | `memory.go` / `MemoryStore` | 長期記憶・日次メモの管理 |
| `pkg/agent` | `users.go` / `UserStore`, `User` | ユーザーディレクトリ永続化 |
| `pkg/providers` | `types.go` / `LLMProvider`, `Message`, `LLMResponse` | LLM 抽象インターフェース |
| `pkg/providers` | `provider.go` / `CreateProvider` | Provider 生成の単一入口 |

## 3. 通信・チャネル系

| パッケージ | 主ファイル / シンボル | 役割 |
| --- | --- | --- |
| `pkg/bus` | `bus.go` / `MessageBus` | inbound / outbound の in-memory 中継 |
| `pkg/bus` | `types.go` / `InboundMessage`, `OutboundMessage` | ランタイム共通メッセージ型 |
| `pkg/channels` | `base.go` / `Channel`, `BaseChannel` | チャネル共通抽象 |
| `pkg/channels` | `manager.go` / `Manager`, `StartAll`, `dispatchOutbound` | チャネル群の初期化・起動・配送 |
| `pkg/channels` | `websocket.go` / `WebSocketChannel`, `handleWS`, `readPump`, `maybeBroadcast` | Android / アプリ接続の主要経路 |
| `pkg/channels` | `telegram.go`, `discord.go`, `slack.go`, `line.go`, `whatsapp.go` | 各外部チャネル実装 |
| `pkg/broadcast` | `broadcast.go` / `Send` | Android `am broadcast` フォールバック |
| `pkg/constants` | `channels.go` / `IsInternalChannel` | `cli`, `system`, `subagent` の内部チャネル定義 |

## 4. ツール系

| パッケージ | 主ファイル / シンボル | 役割 |
| --- | --- | --- |
| `pkg/tools` | `base.go` / `Tool`, `ContextualTool`, `AsyncTool` | ツール抽象 |
| `pkg/tools` | `registry.go` / `ToolRegistry` | 登録、実行、Provider 向け定義変換 |
| `pkg/tools` | `result.go` / `ToolResult` | LLM 向け・ユーザー向け結果表現 |
| `pkg/tools` | `message.go` / `MessageTool` | 現チャネル返信・cross-channel 送信 |
| `pkg/tools` | `android.go` / `AndroidTool`, `toolRequest`, `sendAndWait` | Android device action 呼び出し |
| `pkg/tools` | `response_waiter.go` / `ResponseWaiter`, `DeviceResponseWaiter` | `tool_request` / `tool_response` 同期 |
| `pkg/tools` | `cron.go` / `CronTool` | スケジュール操作と job 実行橋渡し |
| `pkg/tools` | `subagent.go` / `SubagentManager`, `SubagentTool` | 同期/非同期の下位エージェント実行 |
| `pkg/tools` | `mcp.go` / `MCPBridgeTool` | MCP サーバーへの統一アクセス |
| `pkg/tools` | `filesystem.go`, `edit.go`, `copy_file.go` | ワークスペース中心のファイル操作 |
| `pkg/tools` | `shell.go` | `ExecTool` によるシェル実行 |
| `pkg/tools` | `memory.go`, `user.go`, `skills.go`, `web.go`, `exit.go` | 補助機能群 |

### ツール登録の実際

`pkg/agent/loop.go` の `createToolRegistry()` と `NewAgentLoop()` が登録箇所です。

- 基本ファイル操作
- `ExecTool`（`Tools.Exec.Enabled` 時のみ）
- `WebSearchTool`, `WebFetchTool`
- `AndroidTool`（`Tools.Android.Enabled` 時のみ）
- `MessageTool`
- `SpawnTool`, `ExitTool`, `SubagentTool`
- `UserTool`, `MemoryTool`, `SkillTool`
- `MCPBridgeTool`（`Tools.MCP` があるとき）
- `CronTool`（`cmd/clawdroid/main.go` の `setupCronTool()` で追加）

## 5. 設定・永続化系

| パッケージ | 主ファイル / シンボル | 役割 |
| --- | --- | --- |
| `pkg/config` | `config.go` / `Config`, `LoadConfig`, `DefaultConfig` | 設定定義、ロード、保存、環境変数上書き（設定ファイル存在時） |
| `pkg/config` | `migration.go` | 設定スキーマ移行 |
| `pkg/session` | `manager.go` / `SessionManager`, `Session` | 会話履歴と summary の保存 |
| `pkg/state` | `state.go` / `Manager`, `State` | 最終チャネルや chatID の状態保存 |
| `pkg/skills` | `loader.go` / `SkillsLoader` | `SKILL.md` 探索とロード |
| `pkg/i18n` | `i18n.go`, `messages_*.go` | 翻訳辞書とロケール正規化 |

## 6. サービス系

| パッケージ | 主ファイル / シンボル | 役割 |
| --- | --- | --- |
| `pkg/gateway` | `server.go` / `Server` | HTTP Config API サーバー |
| `pkg/gateway` | `handlers.go` | schema/config の GET/PUT 実装 |
| `pkg/gateway` | `setup.go` | 初回セットアップ API |
| `pkg/gateway` | `auth.go` | Bearer 認証 |
| `pkg/gateway` | `schema.go` / `BuildSchema` | Android 設定 UI 向けスキーマ構築 |
| `pkg/cron` | `service.go` / `CronService`, `CronJob` | 永続化付きスケジューラ |
| `pkg/heartbeat` | `service.go` / `HeartbeatService` | 定期プロンプト実行 |
| `pkg/mcp` | `manager.go` / `Manager`, `ServerInstance` | MCP サーバープロセス/セッション管理 |

## 7. 補助パッケージ

| パッケージ | 主ファイル / シンボル | 役割 |
| --- | --- | --- |
| `pkg/logger` | `logger.go` / `SetLevel`, `InfoCF`, `WarnCF`, `ErrorCF` | シンプルな構造化ログ |
| `pkg/utils` | `string.go`, `media.go` | 文字列切り詰め、media 補助 |

## 8. 依存の見取り図

概念的な依存は次の通りです。

```text
cmd/clawdroid
  ├─ config
  ├─ gateway
  ├─ channels
  ├─ providers
  ├─ agent
  │   ├─ session/state
  │   ├─ tools
  │   ├─ skills
  │   ├─ mcp
  │   └─ i18n/logger/utils
  ├─ cron
  └─ heartbeat
```

境界として重要なのは次の 3 点です。

1. **通信境界**: `bus.InboundMessage` / `bus.OutboundMessage`
2. **LLM 境界**: `providers.LLMProvider`
3. **ツール境界**: `tools.Tool`

この 3 つを軸に読むと、現在の Go バックエンドの責務分離を追いやすいです。
