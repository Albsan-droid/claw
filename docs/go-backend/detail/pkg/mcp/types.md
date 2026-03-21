# pkg/mcp/types.go 詳細設計

## 対象ソース
- `pkg/mcp/types.go`

## 概要
MCP マネージャがサーバー一覧を軽量に返すための要約型を定義する。SDK 依存型を外へ漏らさず、設定上の説明と現在状態だけを持つ薄い DTO である。

## 責務
- `Manager.ListServers()` の返却型を提供する。
- サーバー名、説明、稼働状態だけを保持する。

## 主要な型・関数・メソッド
### `type ServerSummary struct`
- `Name string`
- `Description string`
- `Status string`

## 詳細動作
- 本ファイルは型定義のみで、処理ロジックは持たない。
- `manager.go` の `ListServers()` が `running` / `stopped` をセットして返す用途に使われる。
- コメント上でも MCP SDK の型ではなく Manager 専用の軽量ビューであることを明示している。

## 入出力・副作用・永続化
- 入力: なし（型定義のみ）。
- 出力: なし（型定義のみ）。
- 副作用: なし。
- 永続化: なし。

## 依存関係
- なし（標準ライブラリ依存もなし）。
- 利用側: `pkg/mcp/manager.go`, `pkg/tools/mcp.go`

## エラーハンドリング・制約
- 型定義のみのため直接のエラーハンドリングはない。
- `Status` は文字列で表現されるため、許容値の一貫性は構築側 (`manager.go`) に依存する。
