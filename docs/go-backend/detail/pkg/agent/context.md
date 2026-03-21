# pkg/agent/context.go

## 対象ソース
- `pkg/agent/context.go`

## 概要
`ContextBuilder` は、Go バックエンドのエージェントが LLM に渡すシステムプロンプトとメッセージ配列を組み立てる責務を持つ。ツール一覧、スキル、MCP サーバー、永続メモリ、ユーザー情報、現在のセッション情報を 1 つの文脈に統合し、`providers.Message` 配列へ変換する。

## 責務
- 実行時情報・安全方針・ツール利用方針を含むシステムプロンプトの生成
- スキル、MCP、接続済みチャネル、永続メモリのプロンプト反映
- 現在のチャネル / Chat ID / 入力モード / 解決済みユーザー情報の注入
- 会話履歴中の `assistant.tool_calls` と `tool` 応答の整合性補正
- ツール登録状態に応じた説明文の出し分け

## 主要な型・関数・メソッド
### 型
- `ContextBuilder`
  - `workspace`, `dataDir`: ワークスペースとデータ保存先
  - `skillsLoader`: `skills.SkillsLoader`
  - `memory`: `MemoryStore`
  - `tools`: `*tools.ToolRegistry`
  - `mcpManager`: `*mcp.Manager`
  - `enabledChannels`: 有効チャネル一覧
  - `memoryToolEnabled`: memory ツール登録有無
  - `userStore`: `*UserStore`

### 定数
- `SilentReplyToken = "NO_REPLY"`
  - ユーザー向け返信を送らないときに LLM が返す制御トークン

### 関数・メソッド
- `getGlobalConfigDir() string`
- `NewContextBuilder(workspace, dataDir string) *ContextBuilder`
- `GetMemory() *MemoryStore`
- `GetSkillsLoader() *skills.SkillsLoader`
- `SetToolsRegistry(registry *tools.ToolRegistry)`
- `SetMCPManager(manager *mcp.Manager)`
- `SetEnabledChannels(channels []string)`
- `SetMemoryToolEnabled(enabled bool)`
- `SetUserStore(store *UserStore)`
- `BuildSystemPrompt() string`
- `BuildMessages(history []providers.Message, summary, currentMessage string, media []string, channel, chatID, inputMode string, resolvedUser *User) []providers.Message`
- `LoadBootstrapFiles() string`
- `GetSkillsInfo() map[string]interface{}`
- `AddToolResult(...) []providers.Message`
- `AddAssistantMessage(...) []providers.Message`
- `sanitizeToolMessages(history []providers.Message) []providers.Message`

## 詳細動作
### 初期化
- `NewContextBuilder` は以下 3 系統のスキル探索パスを前提に `skills.NewSkillsLoader` を作る。
  - `dataDir` ベースのユーザーデータ側スキル領域（`SkillsLoader` 内で扱う）
  - `~/.clawdroid/skills`
  - カレントワーキングディレクトリ配下の `skills`
- 同時に `NewMemoryStore(dataDir)` を生成し、以後のメモリ参照に使う。

### `BuildSystemPrompt`
`BuildSystemPrompt` はセクションを順番に配列へ積み上げ、最後に `"\n\n---\n\n"` で連結する。主な構成は次のとおり。
1. 現在時刻・Runtime・Workspace・利用可能ツール
2. Safety
3. Tool Call Style
4. Sub-agents（`spawn` または `subagent` が登録されている場合のみ）
5. Messaging（有効チャネルが 1 つ以上ある場合のみ）
6. Cron（`cron` ツールがある場合のみ）
7. Memory guidance
8. User Management（`user` ツールがある場合のみ）
9. `AGENT.md` / `SOUL.md` / `IDENTITY.md` の内容
10. Skills
11. MCP Servers
12. Connected Channels
13. 実メモリ内容
14. Silent Replies
15. Heartbeats

### セクション生成の条件分岐
- `buildToolsSection` は `ToolRegistry.GetSummaries()` をそのまま列挙する。
- `getMemoryGuidance` は `memoryToolEnabled` により出力が変わる。
  - 有効時: memory ツールの `read_*/write_*` 操作を説明
  - 無効時: `dataDir/memory/...` のファイルパスを直接提示
- `LoadBootstrapFiles` は `dataDir` 直下の `AGENT.md`, `SOUL.md`, `IDENTITY.md` を存在するものだけ読む。`SOUL.md` があると「persona と tone を反映せよ」という追記が入る。
- `buildChannelsSection` は `enabledChannels` に加え、常に `app` エイリアスを末尾に追加する。

### `BuildMessages`
- まず `BuildSystemPrompt()` を呼び、必要に応じて `## Current Session` を追加する。
- `resolvedUser != nil` の場合は `Sender: <name> (ID: <id>)` と `User Notes` を追記する。
- `inputMode` が `voice` または `assistant` のときだけ `voiceModePrompt()` の返す英語プロンプトを末尾へ連結する。
- デバッグログとして、システムプロンプトの文字数・行数・セクション数と、最大 500 文字のプレビューを `logger.DebugCF` で出力する。
- `summary` がある場合は `## Summary of Previous Conversation` を追加する。
- その後、履歴に `sanitizeToolMessages` を適用し、最終的に以下の順で配列を返す。
  1. `role=system` のシステムメッセージ
  2. 補正済み履歴
  3. 現在の `role=user` メッセージ（`media` があればそのまま添付）

### 履歴補正 (`sanitizeToolMessages`)
- 1 回目の走査で、`assistant.ToolCalls[].ID` と `tool.ToolCallID` を別々に収集する。
- 2 回目の走査で次を行う。
  - 対応する `assistant.tool_calls` が存在しない `tool` メッセージを削除
  - 対応する `tool` 応答が存在しない `assistant.ToolCalls` だけを除去
- 補正した箇所は `logger.DebugCF` へ出す。

### 補助メソッドの挙動
- `AddToolResult` は `role=tool` メッセージを 1 件 append する。
- `AddAssistantMessage` は引数 `toolCalls` を使わず、`role=assistant` と `content` だけを append する。
- `GetSkillsInfo` はスキル名一覧と件数を返す。

## 入出力・副作用・永続化
### 入力
- 会話履歴 `[]providers.Message`
- 現在のユーザー入力文字列とメディア data URL 一覧
- チャネル / Chat ID / 入力モード / 解決済みユーザー
- `dataDir` 配下の bootstrap ファイル、memory ファイル、スキル定義

### 出力
- システムプロンプト文字列
- LLM 向け `[]providers.Message`
- スキル情報 `map[string]interface{}`

### 副作用
- `os.ReadFile` による bootstrap ファイル読み込み
- `MemoryStore` 経由のメモリ内容読み出し
- `logger.DebugCF` によるプロンプト統計 / プレビューのログ出力

### 永続化
- このファイル自身は永続化を行わない。
- ただし `LoadBootstrapFiles` / `GetMemoryContext` は既存永続ファイルを参照する。

## 依存関係
- `pkg/logger`
- `pkg/mcp`
- `pkg/providers`
- `pkg/skills`
- `pkg/tools`
- 同一パッケージ内の `MemoryStore`, `User`, `voiceModePrompt`
- 標準ライブラリ: `fmt`, `os`, `path/filepath`, `strings`, `time`

## エラーハンドリング・制約
- `os.UserHomeDir` に失敗した場合、グローバルスキルパスは空文字列になる。
- bootstrap ファイル読み込み失敗は無視され、該当セクションは省略される。
- `tools == nil` のとき動的ツール一覧は生成されない。
- `sanitizeToolMessages` は履歴全体を再構成するが、メッセージ内容自体は改変しない。
- `BuildSystemPrompt` のメモリ実体部分は `"# Memory\n\n" + cb.memory.GetMemoryContext()` で追加される。`GetMemoryContext()` 自身も `# Memory` 見出しを返すため、非空時は見出しが二重になるのが実装上の挙動である。
