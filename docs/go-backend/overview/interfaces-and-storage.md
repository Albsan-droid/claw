# インターフェースとストレージ

## 1. 外部インターフェース

## 1.1 HTTP Config API

`pkg/gateway/server.go` の `Server.Start()` が次のエンドポイントを登録します。

| Method | Path | 実体 | 用途 |
| --- | --- | --- | --- |
| `GET` | `/api/config/schema` | `handleGetSchema()` | UI 向け設定スキーマ取得 |
| `GET` | `/api/config` | `handleGetConfig()` | 現在設定取得 |
| `PUT` | `/api/config` | `handlePutConfig()` | 設定更新 + 再起動要求 |
| `POST` | `/api/setup/init` | `handleSetupInit()` | 初回セットアップ開始 |
| `PUT` | `/api/setup/complete` | `handleSetupComplete()` | セットアップ完了 |

補助実装:

- 認証: `pkg/gateway/auth.go` の `authMiddleware()`
- スキーマ生成: `pkg/gateway/schema.go` の `BuildSchema()`

### 認証仕様

`cfg.Gateway.APIKey` が空でなければ、`GET /api/config/schema`、`GET /api/config`、`PUT /api/config`、`PUT /api/setup/complete` では `Authorization: Bearer <token>` が必要です。比較は `subtle.ConstantTimeCompare()` を使います。

例外として、`POST /api/setup/init` は初回 bootstrap 用のため `authMiddleware()` を通らず、API キー設定前でも呼び出せます。

## 1.2 WebSocket インターフェース

`pkg/channels/websocket.go` に JSON の入出力型があります。

### Go が受ける JSON (`wsIncoming`)

- `content string`
- `sender_id string`
- `images []string`
- `input_mode string`
- `type string`
- `request_id string`

意味:

- 通常メッセージ
- Android 画像付き入力
- `type == "tool_response"` による Android ツール応答

### Go が送る JSON (`wsOutgoing`)

- `content string`
- `type string`

主な `type`:

- 空文字または通常メッセージ
- `status`
- `status_end`
- `error`
- `warning`
- `tool_request`
- `setup_required`

## 1.3 Android broadcast フォールバック

`pkg/broadcast/broadcast.go` の `Send()` は次の Intent を発行します。

- action: `io.clawdroid.AGENT_MESSAGE`
- package: `io.clawdroid`
- extra: `message=<JSON>`

これは Go バックエンドが Termux / Android 上で同居している前提の送信経路です。

## 2. 内部インターフェース

## 2.1 Channel 抽象

`pkg/channels/base.go`:

```go
type Channel interface {
    Name() string
    Start(ctx context.Context) error
    Stop(ctx context.Context) error
    Send(ctx context.Context, msg bus.OutboundMessage) error
    IsRunning() bool
    IsAllowed(senderID string) bool
}
```

`channels.Manager` はこの抽象の上で Telegram / Slack / WebSocket などを同列に扱います。

## 2.2 Tool 抽象

`pkg/tools/base.go`:

```go
type Tool interface {
    Name() string
    Description() string
    Parameters() map[string]interface{}
    Execute(ctx context.Context, args map[string]interface{}) *ToolResult
}
```

拡張インターフェース:

- `ContextualTool` — `SetContext(channel, chatID string)`
- `ActivatableTool` — `IsActive() bool`
- `AsyncTool` — `SetCallback(cb AsyncCallback)`

`ToolRegistry` は `pkg/tools/registry.go` にあります。

## 2.3 LLM Provider 抽象

`pkg/providers/types.go`:

```go
type LLMProvider interface {
    Chat(ctx context.Context, messages []Message, tools []ToolDefinition, model string, options map[string]interface{}) (*LLMResponse, error)
    GetDefaultModel() string
}
```

生成入口は `pkg/providers/provider.go` の `CreateProvider()` で、現行は `NewAnyLLMAdapter(...)` を返します。

## 2.4 User / Messaging 補助抽象

- `pkg/tools/message.go` の `StateResolver`
- `pkg/tools/cron.go` の `JobExecutor`
- `pkg/tools/user.go` で使う `UserDirectory`

これらは AgentLoop 依存を最小化しつつ、state や direct execution を注入するための境界です。

## 2.5 内部メッセージ型

`pkg/bus/types.go`:

- `InboundMessage`
- `OutboundMessage`
- `MessageHandler`

AgentLoop とチャネルの境界はこの 2 型に集約されています。

## 3. 主要な保存先

## 3.1 設定

- パス: `~/.clawdroid/config.json`
- 取得: `cmd/clawdroid/main.go` の `getConfigPath()`
- 読み込み: `pkg/config/config.go` の `LoadConfig()`
- 保存: `SaveConfig()` / `SaveConfigLocked()`

特性:

- JSON 保存
- パーミッション `0600`
- 設定ファイルが存在する場合のみ、読み込み後に `env.Parse(cfg)` で `CLAWDROID_*` 環境変数上書き
- 必要時 `migrateConfig(cfg)` を自動適用

## 3.2 workspace と dataDir

- `Config.WorkspacePath()` → `Agents.Defaults.Workspace`
- `Config.DataPath()` → `Agents.Defaults.DataDir`
- `expandHome()` が `~` を展開

既定値:

- workspace: `~/.clawdroid/workspace`
- dataDir: `~/.clawdroid/data`

出典: `pkg/config/config.go` の `DefaultConfig()`, `WorkspacePath()`, `DataPath()`

## 3.3 セッション履歴

`pkg/session/manager.go` の `SessionManager`:

- ディレクトリ: `{dataDir}/sessions/`
- ファイル: `{sanitizeFilename(sessionKey)}.json`
- 型: `Session{Key, Messages, Summary, Created, Updated}`

保存特性:

- `:` を `_` に置換してファイル名化
- temp file → `os.Rename()` の原子的保存
- メモリ上では元の `sessionKey` を保持

## 3.4 状態ファイル

`pkg/state/state.go` の `Manager`:

- ディレクトリ: `{dataDir}/state/`
- ファイル: `{dataDir}/state/state.json`
- 旧形式移行元: `{dataDir}/state.json`

格納内容:

- `LastChannel`
- `LastChatID`
- `LastMainChannel`
- `ChannelChatIDs`
- `Timestamp`

用途:

- heartbeat の送信先決定
- cross-channel message の `chat_id` 解決
- Android app alias (`channel = "app"`) 解決

## 3.5 メモリ

`pkg/agent/memory.go` の `MemoryStore`:

- 長期記憶: `{dataDir}/memory/MEMORY.md`
- 日次メモ: `{dataDir}/memory/YYYYMM/YYYYMMDD.md`

操作:

- `ReadLongTerm()` / `WriteLongTerm()`
- `ReadToday()` / `AppendToday()`
- `GetRecentDailyNotes()`

## 3.6 ユーザーディレクトリ

`pkg/agent/users.go` の `UserStore`:

- ファイル: `{dataDir}/users.json`
- 型: `usersFile{Users []*User}`
- 旧資産検知: `{dataDir}/USER.md`

`User` の主要フィールド:

- `ID`
- `Name`
- `Channels map[string][]string`
- `Memo []string`

## 3.7 Cron ストア

`pkg/cron/service.go`:

- ファイル: `{dataDir}/cron/jobs.json`
- 型: `CronStore{Version, Jobs}`
- `CronJob` には `Schedule`, `Payload`, `State` を保持

`Payload` には `Message`, `Command`, `Deliver`, `Channel`, `To` があります。

## 3.8 HEARTBEAT.md

`pkg/heartbeat/service.go` の `buildPrompt()` は `{dataDir}/HEARTBEAT.md` を読みます。

- 存在しない場合: `createDefaultHeartbeatTemplate()` を呼ぶ
- 中身が空なら heartbeat 実行なし

## 3.9 media キャッシュ

`pkg/agent/loop.go` の `NewAgentLoop()` で `{dataDir}/media` を作成します。

使い道:

- 受信画像やツール返却画像の永続化
- `PersistMedia()` / `CleanupMediaFiles()` による会話履歴との連動
- `pkg/tools/copy_file.go` から workspace へ移送可能

## 3.10 Skills

`pkg/skills/loader.go` の `SkillsLoader` は呼び出し元によって参照ディレクトリが異なる。

### エージェントランタイム (`pkg/agent/context.go`)

1. `{dataDir}/skills/`
2. `~/.clawdroid/skills/`
3. `<current working dir>/skills/`

### `clawdroid skills` コマンド (`cmd/clawdroid/main.go`)

`skills list` / `skills show` / `skills remove` / `skills uninstall` が使う `SkillsLoader` の探索順は次の通り。

1. `{dataDir}/skills/`
2. `~/.clawdroid/skills/`
3. `~/.clawdroid/clawdroid/skills/`

補足:

- `skills install-builtin` は読み込み順ではなく、コピー元として `./clawdroid/skills/` を参照する。ただし現行実装の `skillsToInstall := []string{}` により、実際にはコピー対象がなく no-op で終了する。
- `skills list-builtin` は `filepath.Dir(cfg.WorkspacePath())/clawdroid/skills/` を参照して builtin skill を列挙する。

どの経路でも、各 skill はディレクトリ配下の `SKILL.md` が実体である。

## 4. 保存形式と排他

### Config

- `Config` 自体が `sync.RWMutex` を内包
- `CopyFrom()` で更新反映
- API 側は「保存成功後にメモリ更新」の順

### SessionManager / State / UserStore

いずれも内部で `sync.RWMutex` を持ち、JSON ファイルを使います。特に `SessionManager.Save()` と `state.Manager.saveAtomic()` は temp file からの rename を使い、途中破損を避けます。

## 5. i18n とロケール伝播

Go バックエンド側の多言語化実装は `pkg/i18n/` にあります。

ロケール流路:

- WebSocket: `handleWS()` がクエリ `locale` を取り、`Metadata["locale"]` に格納
- HTTP Config API: `handleGetSchema()` が `Accept-Language` を `i18n.NormalizeLocale()` に通す
- AgentLoop: `processMessage()` が `opts.Locale` に反映

主要 API:

- `i18n.T(locale, key)`
- `i18n.Tf(locale, key, args...)`

## 6. 代表的な設定項目

`pkg/config/config.go` の `Config` 直下には以下があります。

- `LLM`
- `Agents`
- `Channels`
- `Gateway`
- `Tools`
- `Heartbeat`
- `RateLimits`

バックエンド理解で特に効く項目:

- `Agents.Defaults.RestrictToWorkspace`
- `Agents.Defaults.QueueMessages`
- `Agents.Defaults.MaxToolIterations`
- `Tools.Exec.Enabled`
- `Tools.Android.Enabled`
- `Tools.Memory.Enabled`
- `Tools.MCP`
- `Heartbeat.Enabled`
- `RateLimits.MaxToolCallsPerMinute`
- `RateLimits.MaxRequestsPerMinute`
