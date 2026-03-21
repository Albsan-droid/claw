# pkg/tools/subagent.go 詳細設計

## 対象ソース
- `pkg/tools/subagent.go`

## 概要
独立した LLM + ツール実行ループを持つサブエージェントのタスク管理と、同期・非同期の両ツール表面を提供する。`SpawnTool` が利用するバックグラウンド管理本体と、完了待ちで結果を返す `SubagentTool` を同一ファイルに持つ。

## 責務
- サブエージェントタスクの採番・状態管理・一覧取得を行う。
- バックグラウンド実行 (`Spawn`) と同期実行 (`SubagentTool.Execute`) を提供する。
- `RunToolLoop` を使って独立した会話ループを実行する。
- 完了時に callback 呼び出しと `MessageBus` への通知を行う。

## 主要な型・関数・メソッド
### `type SubagentTask`
- `ID`, `Task`, `Label`, `OriginChannel`, `OriginChatID`, `Status`, `Result`, `Created`

### `type SubagentManager`
- 主なフィールド: `tasks`, `provider`, `defaultModel`, `bus`, `workspace`, `tools`, `maxIterations`, `nextID`
- `NewSubagentManager(provider, defaultModel, workspace, bus)`
- `SetTools(tools *ToolRegistry)`
- `RegisterTool(tool Tool)`
- `Spawn(ctx, task, label, originChannel, originChatID, callback) (string, error)`
- `GetTask(taskID) (*SubagentTask, bool)`
- `ListTasks() []*SubagentTask`
- 内部: `runTask(ctx, task, callback)`

### `type SubagentTool`
- `NewSubagentTool(manager *SubagentManager) *SubagentTool`
- `SetContext(channel, chatID string)`
- `Execute(ctx, args) *ToolResult`

## 詳細動作
### 非同期実行 (`Spawn` / `runTask`)
- `Spawn` は `subagent-%d` 形式で ID を採番し、`Status=running` のタスクをマップへ登録する。
- その後 goroutine で `runTask` を起動する。
- `runTask` は固定 system prompt とユーザー task から会話履歴を作り、`RunToolLoop` を呼ぶ。
- 実行前に `ctx.Done()` を確認し、既にキャンセル済みなら `cancelled` にする。
- 成功時は `task.Status=completed`、失敗時は `failed`、実行中キャンセル検知時は `cancelled` に更新する。
- `callback` があればロック解除後に `ToolResult` を返して通知する。
- `bus != nil` なら `Channel=system`, `SenderID=subagent:<id>`, `ChatID=<originChannel>:<originChatID>` 形式で完了通知を inbound publish する。

### 同期実行 (`SubagentTool.Execute`)
- `task` を必須取得し、`RunToolLoop` を呼んで完了まで待つ。
- `ForUser` は 500 文字で切り詰めた要約、`ForLLM` はラベル・反復回数・全文結果付きの詳細を返す。

## 入出力・副作用・永続化
- 入力: タスク本文、任意ラベル、起動元チャネル文脈、`ToolRegistry`、LLM プロバイダー。
- 出力: タスク一覧、タスク参照、同期/非同期の実行結果。
- 副作用: goroutine 起動、LLM 呼び出し、ツール実行、`MessageBus` publish。
- 永続化: なし。タスク状態はプロセス内メモリのみ。

## 依存関係
- 標準ライブラリ: `context`, `fmt`, `sync`, `time`
- 同一パッケージ: `Tool`, `ToolRegistry`, `RunToolLoop`, `ToolLoopConfig`, `ToolResult`, `ErrorResult`
- 他パッケージ: `pkg/bus`, `pkg/providers`

## エラーハンドリング・制約
- `SubagentTool` / `SpawnTool` ともに `manager == nil` はエラー。
- タスクマップへの追加・設定変更は mutex で保護されるが、`runTask` 冒頭の `task` フィールド更新はタスクポインタへ直接行われる。
- `workspace` フィールドは保持されるが、本ファイル内では直接参照されない。
- メモリ上のタスクはクリーンアップされないため、長時間稼働で件数が増え続ける。
