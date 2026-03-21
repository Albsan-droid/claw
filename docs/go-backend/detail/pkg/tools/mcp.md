# pkg/tools/mcp.go 詳細設計

## 対象ソース
- `pkg/tools/mcp.go`

## 概要
複数の MCP（Model Context Protocol）サーバーを単一ツール `mcp` として LLM へ公開するブリッジである。サーバー一覧取得、各サーバーのツール一覧、ツール呼び出し、リソース読み出しを action ベースで切り替える。

## 責務
- `pkg/mcp.Manager` の操作をツール API に変換する。
- action ごとの必須引数を検証する。
- MCP SDK 型を文字列化して LLM が扱いやすいテキストへ整形する。

## 主要な型・関数・メソッド
### `type MCPBridgeTool struct`
- フィールド: `manager *mcp.Manager`
- `NewMCPBridgeTool(manager *mcp.Manager) *MCPBridgeTool`
- `Execute(ctx, args) *ToolResult`

### 内部メソッド
- `listServers() *ToolResult`
- `getTools(ctx, args) *ToolResult`
- `callTool(ctx, args) *ToolResult`
- `readResource(ctx, args) *ToolResult`

## 詳細動作
- `action` は `mcp_list`, `mcp_tools`, `mcp_call`, `mcp_read_resource` のみ受け付ける。
- `mcp_list` は `Manager.ListServers()` の結果を `- name: description [status]` 形式へ整形する。
- `mcp_tools` は `Manager.GetTools()` で取得した各ツールについて、名前・説明・入力スキーマ JSON を Markdown 風に出力する。
- `mcp_call` は `arguments` が存在し、かつ `map[string]interface{}` の場合のみそのまま渡す。未指定時は `nil` が渡る。
- `mcp_read_resource` はサーバー名と URI をそのまま `Manager.ReadResource()` に渡す。
- すべて成功時は `SilentResult` を返すため、結果は基本的に LLM 文脈用である。

## 入出力・副作用・永続化
- 入力: `action`, `server`, `tool`, `arguments`, `uri`
- 出力: 一覧・説明・実行結果・リソース内容の文字列、またはエラー結果。
- 副作用: MCP サーバー起動や HTTP/stdio 接続確立は `Manager` 側で発生し得る。
- 永続化: なし。

## 依存関係
- 標準ライブラリ: `context`, `encoding/json`, `fmt`, `strings`
- 他パッケージ: `github.com/KarakuriAgent/clawdroid/pkg/mcp`
- 同一パッケージ: `SilentResult`, `ErrorResult`

## エラーハンドリング・制約
- 各 action ごとに必須パラメータが欠けると即エラー。
- `arguments` は object 前提であり、他型は黙って無視される。
- 結果はテキスト化されるため、元の構造情報は整形後の文字列へ落ちる。
