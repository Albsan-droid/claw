# pkg/tools/registry.go 詳細設計

## 対象ソース
- `pkg/tools/registry.go`

## 概要
ツールの登録・検索・実行・定義列挙を一元管理するレジストリ実装である。実行時にはチャネル文脈の注入、非同期コールバックの差し込み、実行ログ記録まで担当する。

## 責務
- ツール名をキーとした登録・取得を提供する。
- 実行時に `ContextualTool` / `AsyncTool` を検出して追加設定を行う。
- `ActivatableTool` を考慮して LLM 向けツール定義を列挙する。
- 実行開始・成功・失敗・非同期開始をログへ出力する。
- レジストリ内容の一覧・件数・人間向けサマリを返す。

## 主要な型・関数・メソッド
### `type ToolRegistry struct`
- `tools map[string]Tool`
- `mu sync.RWMutex`

### コンストラクタ
- `NewToolRegistry() *ToolRegistry`

### 登録・参照
- `Register(tool Tool)`
- `Get(name string) (Tool, bool)`
- `List() []string`
- `Count() int`
- `GetSummaries() []string`

### 実行
- `Execute(ctx, name, args) *ToolResult`
- `ExecuteWithContext(ctx, name, args, channel, chatID, asyncCallback) *ToolResult`

### 定義変換
- `GetDefinitions() []map[string]interface{}`
- `ToProviderDefs() []providers.ToolDefinition`

## 詳細動作
- `Register` は同名ツールがあれば単純に上書きする。
- `ExecuteWithContext` は以下の順で処理する。
  1. 実行開始ログ出力
  2. ツール検索。見つからなければ `tool %q not found` を返す
  3. `ContextualTool` かつ `channel/chatID` が空でなければ `SetContext` 実行
  4. `AsyncTool` かつコールバック指定ありなら `SetCallback` 実行
  5. 実行時間を計測しながら `tool.Execute` 呼び出し
  6. `ToolResult` の `IsError` / `Async` に応じてログレベルを変えて完了記録
- `GetDefinitions` と `ToProviderDefs` は `ActivatableTool.IsActive()` が false のツールを除外する。
- `ToProviderDefs` は `ToolToSchema` の結果から型安全に `name` / `description` / `parameters` を取り出し、`pkg/providers` 型へ詰め替える。

## 入出力・副作用・永続化
- 入力: `Tool` 実装、ツール名、引数、チャネル文脈、非同期コールバック。
- 出力: `ToolResult`、スキーマ一覧、ツール名一覧、件数。
- 副作用: `pkg/logger` へのログ出力、`ContextualTool` / `AsyncTool` への状態注入。
- 永続化: なし。登録状態はプロセス内メモリのみ。

## 依存関係
- 標準ライブラリ: `context`, `fmt`, `sync`, `time`
- 同一パッケージ: `Tool`, `ContextualTool`, `ActivatableTool`, `AsyncTool`, `AsyncCallback`, `ToolResult`, `ToolToSchema`
- 外部/他パッケージ: `github.com/KarakuriAgent/clawdroid/pkg/logger`, `github.com/KarakuriAgent/clawdroid/pkg/providers`

## エラーハンドリング・制約
- 未登録ツールは `ErrorResult(...).WithError(fmt.Errorf("tool not found"))` を返す。
- ツール実装が `nil` を返すことは想定しておらず、防御コードはない。
- 実行中にツール自身が内部状態を持つ場合、レジストリはスレッド安全性を保証しない。保護されるのはマップ操作のみである。
