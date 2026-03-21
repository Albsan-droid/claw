# Go バックエンド → Android ネイティブ移行計画

> この文書は **Android 組み込み APK パスの将来設計** をまとめた移行計画であり、`README.md` / `README.ja.md` / `docs/go-backend/` が記述する **現行実装** を置き換えるものではない。現時点のユーザー向け手順（特に Termux 版）と Go バックエンドの実装詳細はそれらの文書を正とする。以後、本書で **gateway** と書くときは現在の `clawdroid gateway` 実行系全体を指し、設定 API 単体を指す場合は **HTTP Config API** と明記する。

## 1. 動機と目標

### 1.1 現状の問題

ClawDroid は現在、Go シングルバイナリを Android の子プロセス（`libclawdroid.so`）として実行し、WebSocket（`ws://127.0.0.1:18793`）と HTTP（`127.0.0.1:18790`）経由で通信している。この構成には以下の問題がある。

| 問題 | 影響 |
| --- | --- |
| **プロセス管理のオーバーヘッド** | `GatewayProcessManager` による子プロセスの起動・監視・再起動が必要。OS によるプロセスキルで状態が失われる |
| **二重シリアライズ** | すべてのメッセージが Go ↔ JSON ↔ Kotlin の変換を往復する。CPU・メモリの無駄 |
| **Android ツールの間接呼び出し** | `AndroidTool.sendAndWait()` が WebSocket 経由で tool_request を送り、15秒タイムアウトで tool_response を待つ。本来は同一プロセス内の関数呼び出しで済む |
| **二重ストレージ** | セッション履歴を Go 側（JSON ファイル）と Android 側（Room DB）の両方で保持している |
| **APK サイズ** | Go バイナリ（`libclawdroid.so`）が 4 アーキテクチャ分含まれ、APK サイズを増大させる |
| **デバッグの困難さ** | 2 プロセス間の問題追跡が難しい。Go 側のスタックトレースが Android のログに直接現れない |
| **Embedded/Termux の分岐** | ビルドフレーバーによる分岐が設計を複雑にしている |

### 1.2 移行目標

1. **シングルプロセス化**: Go 子プロセスを廃止し、全ロジックを Android プロセス内で実行する
2. **直接 API 呼び出し**: Android ツール（アラーム、カレンダー、連絡先等）をプロセス内の関数呼び出しに変える
3. **統一ストレージ**: Room DB を唯一の永続化先にし、JSON ファイルベースのストレージを廃止する
4. **APK サイズ削減**: Go バイナリ除去により 20-30MB 程度の削減を見込む
5. **Kotlin 技術スタックへの統一**: Coroutines, Flow, Ktor, Room, WorkManager などの Android 標準技術で構築する

### 1.3 移行しないもの

- **CLI モード (`agent`, `cron`, `skills` コマンド)**: APK 内ネイティブ実装では不要。ただし README / README.ja に記載の Termux ワークフローが残る間は、現行 CLI の挙動を参照元として扱う
- **`am broadcast` フォールバック**: 同一プロセスになるため不要
- **DNS/CA 証明書の手動設定**: Android OS のネイティブ設定を使用
- **Termux 版の置き換え戦略**: 本書の直接スコープ外。現行 README の別プロセス手順は当面維持し、ネイティブ APK 経路が安定後に別途配布形態を決める

---

## 2. コンポーネントマッピング

Go バックエンドの 20 コンポーネントと、移行先の Kotlin 実装の対応表。

| # | Go コンポーネント | パッケージ | Kotlin 移行先 | 方針 |
| --- | --- | --- | --- | --- |
| 1 | **AgentLoop** | `pkg/agent/loop.go` | `core/agent` — `AgentLoop` | Coroutine ベースのループに再実装 |
| 2 | **ContextBuilder** | `pkg/agent/context.go` | `core/agent` — `ContextBuilder` | system prompt 組み立てをそのまま移植 |
| 3 | **MemoryStore** | `pkg/agent/memory.go` | `core/agent` — `MemoryRepository` | Room DB に統合 |
| 4 | **UserStore** | `pkg/agent/users.go` | `core/agent` — `UserRepository` | Room DB に統合 |
| 5 | **MessageBus** | `pkg/bus/bus.go` | `core/agent` — `MessageBus` | `SharedFlow` / `Channel` で再実装 |
| 6 | **ChannelManager** | `pkg/channels/manager.go` | `core/channels` — `ChannelManager` | チャネル管理を Kotlin で再実装 |
| 7 | **WebSocketChannel** | `pkg/channels/websocket.go` | 廃止 | 同一プロセスになるため不要 |
| 8 | **外部チャネル** | `pkg/channels/{telegram,discord,slack,line,whatsapp}.go` | `core/channels` — 各 `Channel` 実装 | Ktor HTTP Client で再実装 |
| 9 | **LLMProvider** | `pkg/providers/` | `core/llm` — `LlmProvider` | Ktor HTTP Client + kotlinx.serialization で再実装 |
| 10 | **ToolRegistry** | `pkg/tools/registry.go` | `core/tools` — `ToolRegistry` | interface ベースのレジストリに移植 |
| 11 | **AndroidTool** | `pkg/tools/android.go` | `core/tools` — 各 `Tool` 実装 | 直接関数呼び出しに変更。カテゴリ別に分割 |
| 12 | **その他ツール群** | `pkg/tools/{filesystem,edit,shell,web,memory,message,exit,spawn,subagent,mcp,cron,skills,user}.go` | `core/tools` — 各 `Tool` 実装 | 個別に移植 |
| 13 | **SessionManager** | `pkg/session/manager.go` | `core/data` — `SessionRepository` | Room DB に統合。既存 `MessageDao` を拡張 |
| 14 | **StateManager** | `pkg/state/state.go` | `core/data` — `StateRepository` | DataStore (Preferences) に統合 |
| 15 | **Config** | `pkg/config/config.go` | `core/data` — `ConfigRepository` | DataStore (Proto) に統合 |
| 16 | **Gateway Server** | `pkg/gateway/` | 廃止 | 設定 UI が直接 Repository にアクセスするため不要 |
| 17 | **CronService** | `pkg/cron/service.go` | `core/agent` — `CronScheduler` | WorkManager で再実装 |
| 18 | **HeartbeatService** | `pkg/heartbeat/service.go` | `core/agent` — `HeartbeatWorker` | WorkManager の PeriodicWorkRequest で再実装 |
| 19 | **MCP Manager** | `pkg/mcp/manager.go` | `core/mcp` — `McpManager` | MCP SDK の Kotlin/JVM 版で再実装 |
| 20 | **i18n** | `pkg/i18n/` | Android リソース (`strings.xml`) | 既存の Android i18n システムに統合 |

**注 — Android アクションの分割粒度:**
現行 Go 実装の内部カテゴリは `app`, `ui`, `intent` を含む 13 種だが、README / README.ja / `CLAUDE.md` で設定キーとして公開されている `tools.android.<category>` は 10 カテゴリ（`alarm` ～ `clipboard`）である。移行後もこの **10 個の設定境界** を維持し、`search_apps` / `tap` / `intent` などの中核デバイスプリミティブは `ToolRequestHandler` 直下の共通処理として扱う。

**補足 — 既存 Android コードの再利用箇所:**

| 既存 Kotlin コード | 再利用方法 |
| --- | --- |
| `core/data` — Room DB (`AppDatabase`, `MessageDao`, `MessageEntity`) | セッション履歴の統一ストレージとして拡張 |
| `core/data` — `WebSocketClient` | 外部チャネル実装の通信基盤として参考にする（WebSocket 接続パターン） |
| `core/domain` — `ChatRepository`, `ChatMessage`, `ConnectionState` | ドメインモデルを拡張して agent 内部でも使用 |
| `app/assistant/actions/` — 全 `ActionHandler` | `AndroidTool` を置き換える直接呼び出し先としてそのまま再利用 |
| `app/assistant/` — `ToolRequestHandler`, `DeviceController` | ツール実行の Android 側ロジックをそのまま再利用 |
| `feature/chat` — `ChatViewModel`, `ChatUiState`, Compose UI | UI 層はほぼそのまま維持 |
| `backend/config` — `ConfigViewModel`, 設定 UI | 設定画面はそのまま維持し、データソースを Repository に切り替え |
| `core/domain/usecase/` — 各 UseCase | 既存 UseCase を維持し、新しい Repository に接続 |

---

## 3. 新モジュール構成

既存のマルチモジュール構成を拡張する形で、新モジュールを追加する。

```
android/
├── app/                          # 既存: Activity, Service, DI
│   └── assistant/actions/        # 既存: ActionHandler群（再利用）
├── core/
│   ├── agent/                    # 新規: AgentLoop, ContextBuilder, MessageBus
│   ├── tools/                    # 新規: ToolRegistry, Tool実装群
│   ├── channels/                 # 新規: ChannelManager, 外部チャネル
│   ├── llm/                      # 新規: LlmProvider, LLM API クライアント
│   ├── mcp/                      # 新規: McpManager
│   ├── data/                     # 既存: Room DB, Repository（拡張）
│   ├── domain/                   # 既存: インターフェース, モデル（拡張）
│   └── ui/                       # 既存: テーマ, 共通UI
├── feature/
│   └── chat/                     # 既存: チャットUI（維持）
└── backend/                      # 段階的に縮小
    ├── api/                      # BackendLifecycle は Termux / 互換方針の判断まで残る可能性
    ├── config/                   # 設定UI → core:data に統合後に削除候補
    ├── loader/                   # EmbeddedBackendLifecycle / GatewayProcessManager → 削除対象
    └── loader-noop/              # Termux / 互換方針の判断まで残る可能性
```

### settings.gradle.kts の変更

```kotlin
// 新規追加
include(":core:agent")
include(":core:tools")
include(":core:channels")
include(":core:llm")
include(":core:mcp")

// ネイティブ APK 経路への移行後に削除候補
// include(":backend:config")
// include(":backend:loader")
// Termux / 互換方針の判断までは残る可能性あり
// include(":backend:api")
// include(":backend:loader-noop")
```

### モジュール間の依存関係

```
app
 ├── core:agent
 │    ├── core:tools
 │    │    └── core:domain
 │    ├── core:channels
 │    │    └── core:domain
 │    ├── core:llm
 │    │    └── core:domain
 │    ├── core:mcp
 │    ├── core:data
 │    │    └── core:domain
 │    └── core:domain
 ├── feature:chat
 │    ├── core:domain
 │    ├── core:data
 │    └── core:ui
 └── core:ui
```

---

## 4. 各コンポーネントの実装方針

### 4.1 AgentLoop (`core:agent`)

Go の `AgentLoop.Run()` を Kotlin Coroutine で再実装する。

```kotlin
class AgentLoop(
    private val messageBus: MessageBus,
    private val llmProvider: LlmProvider,
    private val sessionRepository: SessionRepository,
    private val stateRepository: StateRepository,
    private val toolRegistry: ToolRegistry,
    private val contextBuilder: ContextBuilder,
    private val config: ConfigRepository,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val activeProcesses = ConcurrentHashMap<String, Job>()

    fun start() {
        scope.launch {
            messageBus.inbound.collect { msg ->
                handleInbound(msg)
            }
        }
    }

    private suspend fun handleInbound(msg: InboundMessage) {
        val sessionKey = msg.sessionKey.ifEmpty { "${msg.channel}:${msg.chatId}" }
        val existing = activeProcesses[sessionKey]
        if (existing != null) {
            if (config.queueMessages) {
                existing.join()
            } else {
                existing.cancelAndJoin()
            }
        }
        activeProcesses[sessionKey] = scope.launch {
            try {
                processMessage(msg, sessionKey)
            } finally {
                activeProcesses.remove(sessionKey)
                messageBus.publishOutbound(OutboundMessage(
                    channel = msg.channel, chatId = msg.chatId,
                    type = "status_end"
                ))
            }
        }
    }

    private suspend fun processMessage(msg: InboundMessage, sessionKey: String) {
        // 1. locale, input_mode 抽出
        // 2. レート制限チェック
        // 3. コマンド処理 (/show, /list, /switch)
        // 4. ユーザー解決
        // 5. runAgentLoop() へ委譲
    }

    private suspend fun runAgentLoop(opts: ProcessOptions) {
        // 1. 状態記録
        // 2. ツールコンテキスト更新
        // 3. セッション履歴ロード
        // 4. system prompt 構築
        // 5. LLM 反復呼び出し (runLlmIteration)
        // 6. 応答保存・要約
    }

    private suspend fun runLlmIteration(
        messages: MutableList<LlmMessage>,
        sessionKey: String,
        opts: ProcessOptions,
    ): String {
        var iterations = 0
        while (iterations < config.maxToolIterations) {
            val response = llmProvider.chat(messages, toolRegistry.toDefinitions())
            if (response.toolCalls.isEmpty()) return response.content
            // ツール実行ループ
            for (toolCall in response.toolCalls) {
                val result = toolRegistry.execute(toolCall)
                messages.add(LlmMessage.toolResult(toolCall.id, result.forLlm))
            }
            iterations++
        }
        return ""
    }

    fun stop() { scope.cancel() }
}
```

**Go との主な違い:**
- Go channel → Kotlin `SharedFlow` / `Channel`
- goroutine → `CoroutineScope.launch`
- `sync.RWMutex` → `Mutex` (kotlinx.coroutines) または `ConcurrentHashMap`
- `context.Context` → `CoroutineScope` + structured concurrency

### 4.2 LlmProvider (`core:llm`)

Go の `AnyLLMAdapter` を Ktor HTTP Client + kotlinx.serialization で再実装する。

```kotlin
interface LlmProvider {
    suspend fun chat(
        messages: List<LlmMessage>,
        tools: List<ToolDefinition>,
    ): LlmResponse

    val defaultModel: String
}

class KtorLlmProvider(
    private val providerName: String,  // provider/model の provider 部分
    private val modelName: String,
    private val apiKey: String,
    private val baseUrl: String?,
    private val httpClient: HttpClient,
) : LlmProvider {
    // プロバイダごとのリクエスト/レスポンス形式の変換
}
```

**方針:**
- `any-llm-go` ライブラリの代わりに、各プロバイダの REST API を直接呼ぶ
- モデル指定形式は README / README.ja と同じ `provider/model` を維持する
- Phase 1 の必須範囲は OpenAI、Anthropic / Claude、Gemini / Google の 3 系統
- `base_url` は OpenAI 互換トランスポートとして扱い、xAI、DeepSeek、Groq、OpenRouter、Ollama 等は OpenAI 系のリクエスト経路を再利用する
- ストリーミングは将来対応（Phase 4）

### 4.3 MessageBus (`core:agent`)

Go の `MessageBus`（バッファ付き Go channel）を Kotlin Flow で再実装する。

```kotlin
class MessageBus {
    private val _inbound = MutableSharedFlow<InboundMessage>(
        extraBufferCapacity = 100,
        onBufferOverflow = BufferOverflow.SUSPEND,
    )
    val inbound: SharedFlow<InboundMessage> = _inbound

    private val _outbound = MutableSharedFlow<OutboundMessage>(
        extraBufferCapacity = 100,
        onBufferOverflow = BufferOverflow.SUSPEND,
    )
    val outbound: SharedFlow<OutboundMessage> = _outbound

    suspend fun publishInbound(msg: InboundMessage) { _inbound.emit(msg) }
    suspend fun publishOutbound(msg: OutboundMessage) { _outbound.emit(msg) }
}
```

### 4.4 SessionRepository (`core:data`)

Go の `SessionManager`（JSON ファイル）を既存の Room DB に統合する。

**既存テーブル:** `MessageEntity`（チャット UI 用）
**新規テーブル:** `SessionEntity`, `LlmMessageEntity`

```kotlin
@Entity(tableName = "sessions")
data class SessionEntity(
    @PrimaryKey val key: String,
    val summary: String = "",
    val createdAt: Long,
    val updatedAt: Long,
)

@Entity(
    tableName = "llm_messages",
    foreignKeys = [ForeignKey(
        entity = SessionEntity::class,
        parentColumns = ["key"],
        childColumns = ["sessionKey"],
        onDelete = ForeignKey.CASCADE,
    )]
)
data class LlmMessageEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val sessionKey: String,
    val role: String,          // "user", "assistant", "system", "tool"
    val content: String,
    val toolCallId: String? = null,
    val toolCalls: String? = null,  // JSON
    val media: String? = null,      // JSON
    val orderIndex: Int,
    val createdAt: Long,
)
```

**移行メモ:** `SessionEntity.key` には生の `sessionKey`（通常 `channel:chatID`）をそのまま保存する。Go 版の `sanitizeFilename(sessionKey)` は JSON ファイル名の都合だけなので、Room 側へは持ち込まない。

### 4.5 ConfigRepository (`core:data`)

Go の `Config`（JSON ファイル + 環境変数）を Android DataStore に統合する。

```kotlin
interface ConfigRepository {
    val config: StateFlow<AppConfig>
    suspend fun update(block: (AppConfig) -> AppConfig)
    fun getWorkspacePath(): String
    fun getDataPath(): String
}
```

**方針:**
- Proto DataStore で型安全に管理
- `CLAWDROID_*` 環境変数の上書きは廃止（Android では不要）
- 既存の `GatewaySettingsStore` を `ConfigRepository` に統合
- 設定変更時の再起動は不要（同一プロセス内でホットリロード可能）

### 4.6 StateRepository (`core:data`)

Go の `state.Manager`（JSON ファイル）を Preferences DataStore に統合する。

```kotlin
interface StateRepository {
    suspend fun getLastChannel(): String?
    suspend fun getLastMainChannel(): String?
    suspend fun setLastChannel(value: String)
    suspend fun setLastMainChannel(value: String)
    suspend fun getChannelChatId(channel: String): String?
    suspend fun setChannelChatId(channel: String, chatId: String)
}
```

### 4.7 CronScheduler (`core:agent`)

Go の `CronService`（自前の goroutine ループ + JSON ストア）を WorkManager で再実装する。

```kotlin
class CronScheduler(
    private val context: Context,
    private val workManager: WorkManager,
    private val cronJobDao: CronJobDao,
) {
    fun scheduleJob(job: CronJob) {
        when (job.schedule.kind) {
            "at" -> {
                val delay = job.schedule.atMs - System.currentTimeMillis()
                val request = OneTimeWorkRequestBuilder<CronWorker>()
                    .setInitialDelay(delay, TimeUnit.MILLISECONDS)
                    .setInputData(workDataOf("jobId" to job.id))
                    .build()
                workManager.enqueueUniqueWork(job.id, ExistingWorkPolicy.REPLACE, request)
            }
            "every" -> {
                val request = PeriodicWorkRequestBuilder<CronWorker>(
                    job.schedule.everyMs, TimeUnit.MILLISECONDS,
                ).setInputData(workDataOf("jobId" to job.id))
                 .build()
                workManager.enqueueUniquePeriodicWork(
                    job.id, ExistingPeriodicWorkPolicy.UPDATE, request,
                )
            }
            "cron" -> {
                // cron 式 → 次回実行時刻を計算し OneTimeWorkRequest をチェーン
            }
        }
    }
}
```

**注意:** WorkManager の最小間隔は 15 分。Go 版の `EveryMS` が 15 分未満の場合は `AlarmManager` を併用する。

### 4.8 HeartbeatWorker (`core:agent`)

Go の `HeartbeatService`（goroutine ticker）を WorkManager の PeriodicWorkRequest で再実装する。

```kotlin
class HeartbeatWorker(
    context: Context,
    params: WorkerParameters,
    private val agentLoop: AgentLoop,
    private val stateRepository: StateRepository,
) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val prompt = buildPrompt() ?: return Result.success()
        val channel = stateRepository.getLastMainChannel() ?: return Result.success()
        val chatId = stateRepository.getChannelChatId(channel) ?: return Result.success()
        agentLoop.processHeartbeat(prompt, channel, chatId)
        return Result.success()
    }
}
```

### 4.9 ToolRegistry (`core:tools`)

Go の `ToolRegistry` を Kotlin interface ベースで再実装する。

```kotlin
interface Tool {
    val name: String
    val description: String
    val parameters: JsonObject  // JSON Schema
    suspend fun execute(args: Map<String, Any?>): ToolResult
}

interface ContextualTool : Tool {
    fun setContext(channel: String, chatId: String)
}

class ToolRegistry {
    private val tools = mutableMapOf<String, Tool>()

    fun register(tool: Tool) { tools[tool.name] = tool }

    fun toDefinitions(): List<ToolDefinition> =
        tools.values.map { ToolDefinition(it.name, it.description, it.parameters) }

    suspend fun execute(toolCall: ToolCall): ToolResult {
        val tool = tools[toolCall.name]
            ?: return ToolResult.error("Unknown tool: ${toolCall.name}")
        return tool.execute(toolCall.arguments)
    }
}
```

### 4.10 Android ツール → 直接呼び出し

Go の `AndroidTool`（WebSocket 経由の間接呼び出し）を、既存の `ToolRequestHandler` を facade として経由する直接関数呼び出しに変更する。

**重要:** 既存の Android 側では `ToolRequestHandler` が permission 要求、Accessibility 未許可時の誘導、overlay の一時非表示、screenshot/get_ui_tree/tap/swipe 等の中核処理を束ねている。`ActionHandler` だけを直呼びすると機能退行するため、`ToolRequestHandler` 相当の facade を先に作り、その中でカテゴリ別の `ActionHandler` に委譲する設計にする。

**中核デバイスプリミティブとカテゴリツールの切り分け:**
- `ToolRequestHandler` は現在 `search_apps`, `app_info`, `launch_app`, `screenshot`, `get_ui_tree`, `tap`, `swipe`, `text`, `keyevent`, `broadcast`, `intent` を直接処理している
- 一方、設定ドキュメントで公開されている `tools.android.<category>` は `alarm`, `calendar`, `contacts`, `communication`, `media`, `navigation`, `device_control`, `settings`, `web`, `clipboard` の 10 カテゴリである
- 移行後は **中核デバイスプリミティブ + 10 設定可能カテゴリ** という 2 段構成を維持し、`App/UI/Intent` を新しい設定カテゴリとして増やさない

**現在のフロー:**
```
LLM → AndroidTool → WebSocket tool_request → Android ToolRequestHandler
    → ActionHandler.handle() → WebSocket tool_response → AndroidTool
```

**移行後のフロー:**
```
LLM → AndroidToolFacade (Tool実装) → ToolRequestHandler (facade)
    → permission/accessibility チェック → ActionHandler.handle() → ToolResult
```

```kotlin
class AndroidToolFacade(
    private val toolRequestHandler: ToolRequestHandler,
    private val config: ConfigRepository,
) : Tool, ContextualTool {
    override val name = "android"

    override suspend fun execute(args: Map<String, Any?>): ToolResult {
        val action = args["action"] as? String ?: return ToolResult.error("action required")
        if (!isActionEnabled(action)) return ToolResult.error("unknown action: $action")
        // ToolRequestHandler が permission チェック・overlay 制御・
        // accessibility フォールバックを一元管理する
        val response = toolRequestHandler.handleDirect(action, args)
        return response.toToolResult()
    }
}
```

**ツール分割方針:**
Go 版は単一の `AndroidTool` で全アクションを処理していたが、Kotlin 版では設定境界に合わせたカテゴリ別 `Tool` と中核デバイスプリミティブに分ける。ただし、各ツールは `ToolRequestHandler` を経由して cross-cutting な処理（permission、accessibility、overlay）を共有する。

| 区分 | Tool クラス | 再利用する既存コード |
| --- | --- | --- |
| 中核デバイスプリミティブ | `DeviceTool` | `ToolRequestHandler` 直下の `search_apps` / `screenshot` / `intent` 等 |
| Alarm | `AlarmTool` | `ToolRequestHandler` → `AlarmActionHandler` |
| Calendar | `CalendarTool` | `ToolRequestHandler` → `CalendarActionHandler` |
| Contacts | `ContactsTool` | `ToolRequestHandler` → `ContactsActionHandler` |
| Communication | `CommunicationTool` | `ToolRequestHandler` → `CommunicationActionHandler` |
| Media | `MediaTool` | `ToolRequestHandler` → `MediaActionHandler` |
| Navigation | `NavigationTool` | `ToolRequestHandler` → `NavigationActionHandler` |
| DeviceControl | `DeviceControlTool` | `ToolRequestHandler` → `DeviceControlActionHandler` |
| Settings | `SettingsTool` | `ToolRequestHandler` → `SettingsActionHandler` |
| Web | `WebTool` | `ToolRequestHandler` → `WebActionHandler` |
| Clipboard | `ClipboardTool` | `ToolRequestHandler` → `ClipboardActionHandler` |

### 4.11 外部チャネル (`core:channels`)

Go の各チャネル実装を Ktor HTTP Client で再実装する。

**Android バックグラウンド制約への対応:**

外部チャネル（Telegram long polling、Slack Socket Mode、LINE Webhook、Discord WebSocket）は長時間接続を必要とする。Android のバックグラウンド制約（Doze、App Standby、プロセスキル）に対応するため、以下の設計を採用する。

1. **Foreground Service**: 外部チャネルが 1 つ以上有効な場合は、接続維持専用の `ChannelService`（Foreground Service）を起動し常時通知を表示する。現在の `AssistantService` はオーバーレイ / 音声用、`GatewayService` は Go バックエンド常駐用なので、それぞれの UI 責務と混ぜず、長時間接続・再接続・起動復元だけを `ChannelService` に集約する
2. **Doze 対応**: Foreground Service は Doze の maintenance window で接続を維持できる。ただし Deep Doze では接続が切れる可能性があるため、再接続ロジックを組み込む
3. **Webhook 受信（LINE）**: LINE Webhook はサーバー側で HTTP を受ける必要がある。Android 端末単体では公開 HTTP サーバーを立てられないため、以下のいずれかを採用する:
   - FCM (Firebase Cloud Messaging) + Webhook → FCM 変換サーバー
   - 定期ポーリングによる代替実装
   - 外部チャネルは将来的にコンパニオンサーバーに移すことも検討
4. **プロセスキル対応**: `BootReceiver` + `WorkManager` の組み合わせで、プロセスキル後にサービスを再起動する

```kotlin
interface Channel {
    val name: String
    suspend fun start()
    suspend fun stop()
    suspend fun send(msg: OutboundMessage)
    val isRunning: Boolean
}

class TelegramChannel(
    private val httpClient: HttpClient,
    private val config: TelegramConfig,
    private val messageBus: MessageBus,
) : Channel {
    // Telegram Bot API を Ktor で呼び出し
    // Long polling で受信
    // Foreground Service 内で coroutine を維持
}
```

**スコープ判断:** Phase 3 までのネイティブ agent 対象は app チャネル（アプリ内会話）のみとし、外部チャネルは **Phase 4 の機能互換フェーズ** として扱う。したがって、ネイティブ agent を組み込み APK の既定経路にする条件と、Go バックエンド経由の外部チャネル経路を撤去する条件は分けて評価する。

### 4.12 MCP Manager (`core:mcp`)

Go の `mcp.Manager` を MCP SDK の Kotlin/JVM 版で再実装する。

```kotlin
class McpManager(
    private val configs: Map<String, McpServerConfig>,
) {
    private val servers = ConcurrentHashMap<String, McpServerInstance>()

    suspend fun getTools(serverName: String): List<McpTool> { /* ... */ }
    suspend fun callTool(serverName: String, toolName: String, args: Map<String, Any?>): String { /* ... */ }
    suspend fun readResource(serverName: String, uri: String): String { /* ... */ }
}
```

**方針:**
- `tools.mcp` の設定形状（`command` / `args` / `env`, `url` / `headers`, `idle_timeout`）は現行 README と互換に保つ
- Phase 4 の必須範囲は HTTP/SSE トランスポート。Android 上の stdio サーバーは制約が大きいため、Kotlin/JVM SDK または安全なプロセス管理が整うまでは後続対応 / 開発用途限定扱いにする
- アイドルタイムアウトは Go 版と同じ 300 秒既定

### 4.13 MemoryRepository (`core:data`)

Go の `MemoryStore`（マークダウンファイル）を Room DB に統合する。

```kotlin
@Entity(tableName = "memories")
data class MemoryEntity(
    @PrimaryKey val type: String,  // "long_term" or "daily:YYYYMMDD"
    val content: String,
    val updatedAt: Long,
)
```

**移行メモ:**
- `memory/MEMORY.md` → `MemoryEntity(type = "long_term")`
- `memory/YYYYMM/YYYYMMDD.md` → `MemoryEntity(type = "daily:YYYYMMDD")`
- マークダウン本文は変換せず、そのまま `content` に保存する
- `ContextBuilder` は現行 README と同様に `getRecentDailyNotes(3)` を使い、直近 3 日分だけを system prompt に含める

### 4.14 UserRepository (`core:data`)

Go の `UserStore`（JSON ファイル）を Room DB に統合する。

```kotlin
@Entity(tableName = "users")
data class UserEntity(
    @PrimaryKey val id: String,
    val name: String,
    val channels: String,  // JSON: Map<String, List<String>>
    val memo: String,      // JSON: List<String>
)
```

### 4.15 i18n

Go の `pkg/i18n`（コード内辞書）を Android の標準 `strings.xml` リソースに統合する。

**方針:**
- `i18n.T(locale, key)` の呼び出しを `context.getString(R.string.xxx)` に置き換え
- Go 側のメッセージキー（`messages_status.go`, `messages_config.go`, `messages_agent.go`, `messages_channel.go`）を `strings.xml` に移植
- system prompt 内のテキストは `core:agent` 内に定数として保持（LLM 向けのため i18n 不要な部分もある）

### 4.16 SkillsLoader

Go の `SkillsLoader`（ファイルシステム探索）を Kotlin で再実装する。

```kotlin
class SkillsLoader(
    private val dataDir: File,
    private val globalSkillsDir: File,
    private val builtinSkillsDir: File,
) {
    fun loadSkills(): List<Skill> {
        val dirs = listOf(
            File(dataDir, "skills"),
            globalSkillsDir,
            builtinSkillsDir,
        )
        val seen = mutableSetOf<String>()
        return dirs.flatMap { dir ->
            dir.listFiles()?.filter { it.isDirectory }?.mapNotNull { skillDir ->
                if (!seen.add(skillDir.name)) return@mapNotNull null
                val skillFile = File(skillDir, "SKILL.md")
                if (skillFile.exists()) Skill(skillDir.name, skillFile.readText()) else null
            } ?: emptyList()
        }
    }
}
```

**探索順:** 現行 README / README.ja / Go 実装と同じく、`{dataDir}/skills` → `~/.clawdroid/skills` → 組み込みスキルの順で探索し、同名スキルは先勝ちにする。

---

## 5. データモデル・インターフェース定義

### 5.1 LLM メッセージ型

```kotlin
@Serializable
data class LlmMessage(
    val role: String,          // "system", "user", "assistant", "tool"
    val content: String = "",
    val toolCallId: String? = null,
    val toolCalls: List<ToolCall>? = null,
    val media: List<String>? = null,
)

@Serializable
data class ToolCall(
    val id: String,
    val name: String,
    val arguments: Map<String, JsonElement>,
)

@Serializable
data class LlmResponse(
    val content: String,
    val toolCalls: List<ToolCall>,
    val usage: UsageInfo? = null,
)

@Serializable
data class UsageInfo(
    val promptTokens: Int,
    val completionTokens: Int,
    val totalTokens: Int,
)
```

### 5.2 ツール定義

```kotlin
@Serializable
data class ToolDefinition(
    val name: String,
    val description: String,
    val parameters: JsonObject,
)

data class ToolResult(
    val forLlm: String,
    val forUser: String? = null,
    val media: List<String>? = null,
    val isError: Boolean = false,
    val isSilent: Boolean = false,
    val isAsync: Boolean = false,
) {
    companion object {
        fun success(content: String) = ToolResult(forLlm = content)
        fun silent(content: String) = ToolResult(forLlm = content, isSilent = true)
        fun error(message: String) = ToolResult(forLlm = message, isError = true)
    }
}
```

### 5.3 バスメッセージ型

```kotlin
data class InboundMessage(
    val channel: String,
    val senderId: String,
    val chatId: String,
    val content: String,
    val media: List<String> = emptyList(),
    val sessionKey: String = "",
    val metadata: Map<String, String> = emptyMap(),
)

data class OutboundMessage(
    val channel: String,
    val chatId: String,
    val content: String = "",
    val type: String = "",  // "", "status", "status_end", "error", "warning"
)
```

### 5.4 Repository インターフェース

```kotlin
// core:domain
interface SessionRepository {
    suspend fun getOrCreate(key: String): Session
    suspend fun addMessage(sessionKey: String, message: LlmMessage)
    suspend fun getHistory(sessionKey: String): List<LlmMessage>
    suspend fun getSummary(sessionKey: String): String
    suspend fun setSummary(sessionKey: String, summary: String)
    suspend fun truncateHistory(sessionKey: String, keepLast: Int)
    suspend fun setHistory(sessionKey: String, history: List<LlmMessage>)
}

interface ConfigRepository {
    val config: StateFlow<AppConfig>
    suspend fun update(block: (AppConfig) -> AppConfig)
    fun getWorkspacePath(): String
    fun getDataPath(): String
}

interface StateRepository {
    suspend fun getLastChannel(): String?
    suspend fun getLastMainChannel(): String?
    suspend fun setLastChannel(value: String)
    suspend fun setLastMainChannel(value: String)
    suspend fun getChannelChatId(channel: String): String?
    suspend fun setChannelChatId(channel: String, chatId: String)
}

interface MemoryRepository {
    suspend fun readLongTerm(): String
    suspend fun writeLongTerm(content: String)
    suspend fun readToday(): String
    suspend fun appendToday(content: String)
    suspend fun getRecentDailyNotes(days: Int): List<DailyNote>
}

interface UserRepository {
    suspend fun getAll(): List<User>
    suspend fun resolveByChannelId(channel: String, senderId: String): User?
    suspend fun save(user: User)
    suspend fun delete(userId: String)
}
```

---

## 6. 移行フェーズ

### Phase 1: 基盤 + 設定 + データ移行 (core:domain, core:data, core:llm)

**目標:** 新モジュールの骨格を作り、データ層・LLMクライアント・設定管理を動作させる。設定 UI とセットアップウィザードを HTTP Config API から `ConfigRepository` 直接アクセスに切り替える。

**作業内容:**
1. `core:domain` にインターフェースとデータモデルを追加
   - `LlmMessage`, `ToolCall`, `ToolDefinition`, `ToolResult`
   - `InboundMessage`, `OutboundMessage`
   - `SessionRepository`, `ConfigRepository`, `StateRepository`, `MemoryRepository`, `UserRepository`
2. `core:data` の Room DB を拡張
   - `SessionEntity`, `LlmMessageEntity`, `MemoryEntity`, `UserEntity`, `CronJobEntity` を追加
   - 既存の `MessageEntity` との共存を維持
   - 各 Repository 実装を追加
3. `core:llm` モジュールを新規作成
   - `LlmProvider` インターフェース
   - `KtorLlmProvider` 実装（Anthropic, OpenAI, Gemini 対応）
4. `core:data` に `ConfigRepository` を DataStore で実装
   - Go 版 `Config` の全フィールドを `AppConfig` データクラスに定義
   - `StateRepository` を Preferences DataStore で実装
5. **設定 UI の接続切り替え**
   - `ConfigApiClient`（HTTP 経由）を `ConfigRepository`（DataStore 直接）に置き換え
   - `SetupViewModel` / `SetupApiClient` を `ConfigRepository` に接続
   - `GatewaySettingsStore` を `ConfigRepository` に統合
   - degraded mode（LLM 設定不備時）の復旧経路を `ConfigRepository` ベースで再実装
6. **既存データの移行（レガシー資産取り込み）**
   - Room の schema migration は **Room テーブル追加だけ** に使い、Go 側の JSON / マークダウン / メディア取り込みは `LegacyDataImporter` の単発起動タスクに分離する
   - 理由: DataStore 書き込み、アプリ内部ファイルコピー、メディア パス再マッピング、再試行 / ロールバックを Room Migration に押し込まないため
   - importer は `legacy_go_import_version` と完了済みデータ種別をアプリ内部設定に保存し、冪等 / 再開可能にする
   - 移行対象と方法:

| Go 側ファイル | 移行先 | 方法 |
| --- | --- | --- |
| `~/.clawdroid/config.json` | `ConfigRepository` (DataStore) | importer が JSON を読み込み、DataStore に書き込む |
| `{dataDir}/sessions/*.json` | `SessionEntity` + `LlmMessageEntity` (Room) | importer が legacy JSON をパースし、各 session を 1 トランザクションで INSERT |
| `{dataDir}/users.json` | `UserEntity` (Room) | importer が JSON をパースし INSERT |
| `{dataDir}/memory/MEMORY.md` | `MemoryEntity` (Room) | importer がマークダウンをそのまま読み込む |
| `{dataDir}/memory/YYYYMM/*.md` | `MemoryEntity` (Room) | importer がディレクトリ走査し `daily:YYYYMMDD` として保存 |
| `{dataDir}/cron/jobs.json` | `CronJobEntity` (Room) | importer が JSON をパースし INSERT |
| `{dataDir}/state/state.json` | `StateRepository` (DataStore) | importer が JSON を読み込み DataStore に書き込む |
| `{dataDir}/HEARTBEAT.md` | アプリ内部ファイル | importer がそのままコピー |
| `{dataDir}/media/*` | アプリ内部ディレクトリ | importer が先にコピーし、取り込んだ履歴内の参照先を新パスへ再マッピング |

   - `SessionEntity.key` には import 時に復元した生の `channel:chatID` を保存する
   - 移行失敗時はソースファイルを削除せず、未完了のデータ種別だけ再試行できる状態を保つ
   - この文書ではソース削除を完了条件にしない。クリーンアップはネイティブ経路が既定化した後の後続対応とする

**依存関係:** なし（最初のフェーズ）

**検証:**
- LLM API の呼び出しが正常に動作すること
- Room DB の CRUD が正常に動作すること
- DataStore の読み書きが正常に動作すること
- 設定 UI が HTTP API を介さず `ConfigRepository` で動作すること
- セットアップウィザードが正常に完了すること
- 既存 Go 側データが Room/DataStore に正しく移行されること

### Phase 2: AgentLoop + ToolRegistry + 要約 (core:agent, core:tools)

**目標:** メッセージ受信 → LLM 呼び出し → ツール実行 → 応答返却の一連のフローを動作させる。要約・圧縮・skills も含め、現行挙動との差を最小化する。

**作業内容:**
1. `core:tools` モジュールを新規作成
   - `Tool`, `ContextualTool` インターフェース
   - `ToolRegistry`
   - 基本ツール群: `ReadFileTool`, `WriteFileTool`, `ListDirTool`, `EditFileTool`, `CopyFileTool`
   - `WebFetchTool`, `WebSearchTool`
   - `MessageTool`, `ExitTool`
   - `MemoryTool`, `UserTool`, `SkillTool`
   - `SubagentTool`, `SpawnTool`
2. `core:agent` モジュールを新規作成
   - `MessageBus`
   - `AgentLoop`
   - `ContextBuilder`（skills、MCP サマリーを含む system prompt 構築）
   - `RateLimiter`
   - `SkillsLoader` の移植
3. **要約・圧縮ロジックの移植**
   - `maybeSummarize`: 履歴 20 件超、または推定トークン数が `contextWindow * 75%` 超で非同期要約を 1 session 1 本だけ起動
   - `summarizeSession`: 直近 4 メッセージを残し、それ以前の `user` / `assistant` メッセージを要約対象にする。要約対象が 10 件超なら 2 分割要約 + マージを行う
   - `forceCompression`: context limit エラー時に `history[0]` + 圧縮ノート + 後半 + 最終メッセージへ切り詰め、tool call / tool response の境界を壊さない
   - 破棄対象のメディアはクリーンアップし、Go 実装のしきい値・順序と揃うことを Phase 2 の互換条件にする
4. 既存の `ChatRepositoryImpl` を修正し、`AgentLoop` に接続
   - Go バックエンド経由の WebSocket 通信を、直接の `MessageBus.publishInbound()` に置き換え
5. i18n メッセージの `strings.xml` への移植

**依存関係:** Phase 1

**検証:**
- テキストメッセージ送信 → LLM 応答が返ること
- ファイル操作ツールが正常に動作すること
- セッション履歴が Room DB に保存されること
- 長時間会話で要約・圧縮が正常に発動すること
- skills が ContextBuilder に反映されること

### Phase 3: Android ツール統合 + Cron/Heartbeat (core:tools 拡張)

**目標:** Android デバイス操作を直接関数呼び出しに移行し、定期実行機能を完成させる。

**作業内容:**
1. `core:tools` に Android ツール群を追加
   - `ToolRequestHandler` を facade として経由する `Tool` 実装（10 設定可能カテゴリ + 中核デバイスプリミティブ）
   - permission チェック・accessibility 誘導・overlay 制御を `ToolRequestHandler` で一元管理
   - スクリーンショット: `AccessibilityScreenshotSource` を直接呼び出し
   - UI ツリー: `ClawDroidAccessibilityService` を直接呼び出し
2. CronScheduler を WorkManager + AlarmManager で実装
   - WorkManager: 15分以上の間隔のジョブ
   - AlarmManager: 15分未満の exact ジョブ（`SCHEDULE_EXACT_ALARM` 権限が必要）
   - デバイス再起動時の再登録（`BootReceiver`）
3. HeartbeatWorker を WorkManager で実装
4. ExecTool の移植（shell 実行）
5. サブエージェントの完全移植

**依存関係:** Phase 2

**検証:**
- 全 Android ツール（10 設定可能カテゴリ + 中核デバイスプリミティブ）が直接呼び出しで動作すること
- 15秒タイムアウトが不要になったこと
- permission 未許可時の誘導が正常に機能すること
- Cron ジョブがスケジュール通りに実行されること
- Heartbeat が定期的に実行されること

### Phase 4: 外部チャネル + MCP + 組み込み APK 経路の Go バックエンド依存除去 (core:channels, core:mcp)

**目標:** 外部メッセージングサービスと MCP サーバーの機能互換を完了し、組み込み APK 経路から Go バックエンド依存を外す。

**作業内容:**
1. `core:channels` モジュールを新規作成
   - `Channel` インターフェース
   - `ChannelManager`
   - `TelegramChannel`（Ktor HTTP Client + Long Polling）
   - `DiscordChannel`（Ktor WebSocket）
   - `SlackChannel`（Ktor HTTP Client + Socket Mode）
   - `LineChannel`（FCM + Webhook 変換 or 定期ポーリング）
   - `WhatsAppChannel`（Ktor HTTP Client）
   - Foreground Service (`ChannelService`) による常駐モデル
   - Doze / プロセスキル対応の再接続ロジック
2. `core:mcp` モジュールを新規作成
   - `McpManager`
   - HTTP/SSE トランスポートの MCP クライアントを Phase 4 の必須範囲とする
   - stdio トランスポートは SDK / プロセス管理が成立する場合のみ後続対応で互換を取る
3. **組み込み APK 経路の Go バックエンド依存除去**
   - `backend/loader`, `GatewayService`, `GatewayProcessManager`, `EmbeddedBackendLifecycle` の削除
   - APK から `libclawdroid.so` を除去し、ネイティブ agent を既定経路にする
   - Android ビルド / release pipeline から Go バイナリ同梱ステップを外す
   - `BackendLifecycle` / `loader-noop` / Termux 配布物の扱いは README / README.ja と整合する別の配布形態判断として切り分ける
4. Go バックエンドの設計ドキュメント群の更新

**依存関係:** Phase 3

**検証:**
- Telegram, Discord, Slack, LINE, WhatsApp の各チャネルでメッセージ送受信が動作すること
- Foreground Service でチャネル接続が維持されること
- Doze 解除後に再接続されること
- MCP サーバーへのツール呼び出しが動作すること
- `libclawdroid.so` なしで組み込み APK がビルド・動作すること
- `backend/loader` 除去後に Android ビルドが通ること

---

## 7. 簡素化するもの・複雑化するもの

### 簡素化するもの

| 項目 | 理由 |
| --- | --- |
| **Android ツール呼び出し** | WebSocket 往復 + 15秒タイムアウト → 直接関数呼び出し（ミリ秒単位） |
| **Go バックエンド常駐管理** | `GatewayProcessManager`, `GatewayService`, `EmbeddedBackendLifecycle` が不要に。`BootReceiver` は外部チャネル自動復旧が必要な場合のみ残る |
| **シリアライズ** | Go ↔ JSON ↔ Kotlin の二重変換が消滅 |
| **ストレージ** | Go JSON ファイル + Room DB の二重管理 → Room DB に統一 |
| **組み込み APK 配線** | WebSocket と backend loader 前提の配線が不要に |
| **設定 API** | HTTP Gateway 経由 → Repository 直接アクセス |
| **デバッグ** | 単一プロセスのスタックトレースで完結 |
| **組み込み APK リリース** | APK への Go バイナリ同梱とクロスコンパイルが不要に（Termux 成果物を残す場合は別扱い） |
| **broadcast フォールバック** | `am broadcast` 経路が不要に |
| **DNS/CA 設定** | Android OS のネイティブ設定を使用 |

### 複雑化するもの

| 項目 | 理由 | 対策 |
| --- | --- | --- |
| **LLM クライアント** | `any-llm-go` の代わりに自前実装が必要 | `provider/model` と OpenAI 互換 `base_url` を維持し、OpenAI 系リクエスト経路を再利用する |
| **外部チャネルの常駐** | Go はサーバープロセスとして常駐が自然だが、Android ではバックグラウンド制約（Doze、プロセスキル）がある | Foreground Service + 再接続ロジックで対応。LINE Webhook は FCM 変換サーバーまたはポーリングで代替 |
| **外部チャネル** | Go の豊富な HTTP/WebSocket ライブラリの代わりに Ktor を使用 | Ktor は十分成熟しており、問題は少ない |
| **MCP サポート** | Go SDK の代わりに Kotlin/JVM 版が必要 | Phase 4 は HTTP/SSE を必須範囲とし、stdio 互換は後続対応で扱う |
| **ファイルシステムツール** | Go のファイル操作は簡潔だが、Android ではパーミッションが関わる | `RestrictToWorkspace` 制約により影響は限定的 |
| **Cron 式の解析** | Go の `gronx` ライブラリの代わりが必要 | `cron-utils` ライブラリ（Java）を使用 |
| **並行処理モデル** | Go の goroutine + channel は非常に簡潔 | Kotlin Coroutines + Flow は同等の表現力を持つが、学習コストがある |

---

## 8. テスト戦略

### 8.1 Unit テスト

各モジュールの個別コンポーネントをテストする。

| 対象 | テスト内容 | ツール |
| --- | --- | --- |
| `LlmProvider` | リクエスト/レスポンスの変換、エラーハンドリング | MockWebServer |
| `ToolRegistry` | ツール登録、検索、実行 | JUnit5 + Mockk |
| 各 `Tool` 実装 | 引数バリデーション、実行結果 | JUnit5 + Mockk |
| `AgentLoop` | メッセージ処理フロー、セッション管理 | JUnit5 + Turbine (Flow テスト) |
| `ContextBuilder` | system prompt の組み立て | JUnit5 |
| `SessionRepository` | CRUD 操作 | Room のインメモリ DB |
| `ConfigRepository` | 読み書き、デフォルト値 | DataStore テストライブラリ |
| `MessageBus` | pub/sub の動作、バッファリング | JUnit5 + Turbine |
| `CronScheduler` | スケジュール計算、ジョブ登録 | WorkManager テストライブラリ |
| `ChannelManager` | チャネル初期化、配送ルール | JUnit5 + Mockk |

### 8.2 Integration テスト

コンポーネント間の連携をテストする。

| テストシナリオ | 検証内容 |
| --- | --- |
| **メッセージ → 応答フロー** | MessageBus → AgentLoop → LlmProvider (Mock) → MessageBus |
| **ツール実行フロー** | AgentLoop → ToolRegistry → Tool → ToolResult → LLM 再呼び出し |
| **セッション永続化** | メッセージ送信 → Room DB 保存 → アプリ再起動 → 履歴復元 |
| **設定変更** | ConfigRepository 更新 → AgentLoop への反映 |
| **Android ツール** | AgentLoop → AlarmTool → AlarmActionHandler → ToolResult |

### 8.3 E2E テスト

実際の LLM API を使った（またはモックサーバーを使った）エンドツーエンドテスト。

| テストシナリオ | 検証内容 |
| --- | --- |
| **基本会話** | テキスト送信 → LLM 応答 → UI 表示 |
| **ツール使用会話** | ファイル操作を含む会話が正常に完了すること |
| **Android ツール** | 「アラームをセットして」→ アラーム設定 → 結果応答 |
| **外部チャネル** | Telegram からのメッセージ → 応答 → Telegram に送信 |
| **長時間会話** | 要約・圧縮が発動し、コンテキスト超過なく継続すること |
| **Cron 実行** | スケジュールされたジョブが時刻通りに実行されること |

### 8.4 移行期間中のテスト

Phase 1-3 の移行期間中は、Go バックエンドと Kotlin ネイティブの両方が動作する状態を維持する（少なくとも組み込み APK 経路の backend loader 系は Phase 4 まで残す）。

- **Feature Flag**: `useNativeAgent` フラグで Go バックエンド / Kotlin ネイティブを切り替え可能にする。フラグはユーザー設定とは分離したアプリ内部設定に置き、`ChatRepositoryImpl` / assistant 接続層が `MessageBus.publishInbound()` と WebSocket を切り替える
- **A/B 比較**: 同じ入力に対して両方の出力を比較するテストハーネスを用意する
- **段階的ロールアウト**: Phase 1-2 はデフォルト false、Phase 3 で組み込み APK の既定経路をネイティブに切り替え、Go バックエンド経由の外部チャネル撤去は Phase 4 で評価する
- **データ移行テスト**: Go 側の既存データ（sessions, users, memory, cron, state）が Phase 1 の取り込み処理で正しく Room/DataStore に取り込まれ、再実行しても二重投入されないことを検証する
