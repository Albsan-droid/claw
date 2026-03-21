# pkg/tools/types.go 詳細設計

## 対象ソース
- `pkg/tools/types.go`

## 概要
LLM との対話で用いるメッセージ、ツール呼び出し、利用量、ツール定義、プロバイダー抽象を `pkg/tools` パッケージ内に定義する型ファイルである。内容は `pkg/providers/types.go` と近い構造を持ち、本ファイル自体は定義専用で処理ロジックを持たない。

## 責務
- 会話メッセージの標準構造を定義する。
- ツール呼び出し要求と関数呼び出し情報を表現する。
- LLM 応答とトークン使用量の型を定義する。
- LLM プロバイダー実装が満たすべきインターフェースを示す。
- ツール定義を関数呼び出し形式で表現する。

## 主要な型・関数・メソッド
### `type Message`
- `Role`, `Content`, `ToolCalls`, `ToolCallID` を持つ会話メッセージ。

### `type ToolCall`
- `ID`, `Type`, `Function`, `Name`, `Arguments` を持つツール呼び出し表現。
- `Function` には文字列化済み引数、`Arguments` には map 形式の引数を保持できる。

### `type FunctionCall`
- `Name string`
- `Arguments string`

### `type LLMResponse`
- `Content`, `ToolCalls`, `FinishReason`, `Usage`

### `type UsageInfo`
- `PromptTokens`, `CompletionTokens`, `TotalTokens`

### `type LLMProvider interface`
- `Chat(ctx, messages, tools, model, options)`
- `GetDefaultModel()`

### ツール定義型
- `ToolDefinition`
- `ToolFunctionDefinition`

## 詳細動作
- 本ファイルに関数実装はなく、シリアライズ用タグ付きの構造体定義のみを提供する。
- `ToolCall` は関数呼び出し中心の表現と、簡易な `Name` / `Arguments` の両方を保持できる形で定義されている。
- `LLMProvider` はツール一覧を受け取って会話を進める API 形状を定める。
- 現行の `toolloop.go` や `subagent.go` は `pkg/providers` 側の同等型を直接利用しており、本ファイルは `pkg/tools` 内の独立定義として残っている。

## 入出力・副作用・永続化
- 入力: なし（型定義のみ）。
- 出力: なし（型定義のみ）。
- 副作用: なし。
- 永続化: なし。

## 依存関係
- 標準ライブラリ: `context`
- 関係先: 構造は `pkg/providers/types.go` と対応するが、直接依存はしていない。

## エラーハンドリング・制約
- 型定義のみのため、直接のエラーハンドリングは存在しない。
- 現行の主要処理が `pkg/providers` 型を使っているため、この型群を新規利用する際は二重定義との整合性に注意が必要である。
