# pkg/tools/spawn.go 詳細設計

## 対象ソース
- `pkg/tools/spawn.go`

## 概要
サブエージェントをバックグラウンドで起動する非同期ツールである。`AsyncTool` を実装し、ツール実行時は即座に `AsyncResult` を返しつつ、実処理は `SubagentManager` 側へ委譲する。

## 責務
- 非同期タスク実行要求を `SubagentManager` へ橋渡しする。
- 起動元チャネル・チャット ID をサブエージェントへ渡す。
- 非同期完了通知用の `AsyncCallback` を保持する。

## 主要な型・関数・メソッド
### `type SpawnTool struct`
- `manager *SubagentManager`
- `originChannel string`
- `originChatID string`
- `callback AsyncCallback`

### 主なメソッド
- `NewSpawnTool(manager *SubagentManager) *SpawnTool`
- `SetCallback(cb AsyncCallback)`
- `SetContext(channel, chatID string)`
- `Execute(ctx, args) *ToolResult`

## 詳細動作
- コンストラクタは既定の起動元を `cli/direct` に初期化する。
- `SetContext` が呼ばれると、現在会話のチャネルとチャット ID が上書きされる。
- `Execute` は `task` を必須、`label` を任意で受け取る。
- `manager == nil` の場合は失敗する。
- `manager.Spawn(ctx, task, label, originChannel, originChatID, callback)` を呼び、その戻りメッセージを `AsyncResult` で返す。
- 以後の実処理、タスク状態更新、完了通知、メッセージバス通知は `subagent.go` 側が担う。

## 入出力・副作用・永続化
- 入力: `task`, 任意 `label`, 起動元文脈、非同期コールバック。
- 出力: 非同期開始結果またはエラー結果。
- 副作用: ゴルーチン起動そのものは `SubagentManager.Spawn` 側で発生する。
- 永続化: なし。タスク情報は `SubagentManager` のメモリに保持される。

## 依存関係
- 標準ライブラリ: `context`, `fmt`
- 同一パッケージ: `SubagentManager`, `AsyncCallback`, `AsyncResult`, `ErrorResult`

## エラーハンドリング・制約
- `task` 未指定時はエラー。
- `SubagentManager` 未設定時は `Subagent manager not configured` を返す。
- 非同期ツールであるため、呼び出し時点では最終成否を返さない。
