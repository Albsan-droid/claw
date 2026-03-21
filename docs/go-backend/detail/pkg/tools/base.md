# pkg/tools/base.go 詳細設計

## 対象ソース
- `pkg/tools/base.go`

## 概要
`pkg/tools` 配下の各ツール実装が従う共通契約を定義する基盤ファイルである。ツール名・説明・引数スキーマ・実行関数という最小要件に加え、会話文脈の注入、条件付き有効化、非同期完了通知という拡張点もここで定義する。

## 責務
- 全ツール共通の `Tool` インターフェースを定義する。
- 文脈付きツール向けの `ContextualTool` を定義する。
- LLM へ提示するツール一覧を制御する `ActivatableTool` を定義する。
- バックグラウンド処理向けの `AsyncTool` / `AsyncCallback` を定義する。
- ツール実装を関数呼び出しスキーマへ変換する `ToolToSchema` を提供する。

## 主要な型・関数・メソッド
### `type Tool interface`
- `Name() string`
- `Description() string`
- `Parameters() map[string]interface{}`
- `Execute(ctx context.Context, args map[string]interface{}) *ToolResult`

### `type ContextualTool interface`
- `Tool` を埋め込み、`SetContext(channel, chatID string)` を追加する。
- `registry.go` から呼ばれ、会話中のチャネル・チャット ID をツールへ渡す。

### `type ActivatableTool interface`
- `IsActive() bool`
- `registry.go` がツール定義一覧を構築する際のフィルタ条件として利用する。

### `type AsyncCallback`
- `func(ctx context.Context, result *ToolResult)`
- 非同期ツール完了時にコールバックされる関数型。

### `type AsyncTool interface`
- `Tool` を埋め込み、`SetCallback(cb AsyncCallback)` を追加する。
- `spawn.go` のようなバックグラウンド実行ツールが実装対象となる。

### `func ToolToSchema(tool Tool) map[string]interface{}`
- ツール名・説明・引数 JSON Schema を OpenAI 互換の関数ツール形式へ変換する。

## 詳細動作
- 本ファイル自体はツールを実行しない。実行時制御は `registry.go` が担う。
- `ToolToSchema` は `type=function` を固定し、`tool.Name()`, `tool.Description()`, `tool.Parameters()` をそのまま埋め込む。
- `AsyncTool` は「即時返却 + 後続通知」を実現するための約束事だけを定義し、ゴルーチン管理そのものは各実装に委ねる。

## 入出力・副作用・永続化
- 入力: ツール実装オブジェクト、実行時 `context.Context`、ツール引数。
- 出力: `ToolResult` またはツール定義スキーマ。
- 副作用: なし。インターフェース定義とスキーマ生成のみ。
- 永続化: なし。

## 依存関係
- 標準ライブラリ: `context`
- 同一パッケージ: `ToolResult`（`pkg/tools/result.go`）
- 利用側: `ToolRegistry`（`registry.go`）、個別ツール実装全般

## エラーハンドリング・制約
- 本ファイル内に直接のエラーハンドリングはない。
- `Parameters()` は実質的に JSON Schema 互換 `map[string]interface{}` を返す前提で設計されている。
- `ContextualTool` / `ActivatableTool` / `AsyncTool` は任意実装であり、未実装でも `Tool` としては成立する。
