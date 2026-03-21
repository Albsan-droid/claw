# pkg/providers/types.go

## 対象ソース
- `pkg/providers/types.go`

## 概要
LLM 接続層で共通利用する基本型を定義する。メッセージ、ツール定義、ツールコール、使用量、プロバイダインターフェースがここにまとまっている。

## 責務
- LLM とのやり取りで使う共通 DTO の提供
- JSON シリアライズ向け struct tag の定義
- プロバイダ実装が従うインターフェースの定義

## 主要な型・関数・メソッド
### 型
- `ToolCall`
  - `ID`, `Type`, `Function`, `Name`, `Arguments`
- `FunctionCall`
  - `Name`, `Arguments`
- `LLMResponse`
  - `Content`, `ToolCalls`, `FinishReason`, `Usage`
- `UsageInfo`
  - `PromptTokens`, `CompletionTokens`, `TotalTokens`
- `Message`
  - `Role`, `Content`, `Media`, `ToolCalls`, `ToolCallID`
- `ToolDefinition`
  - `Type`, `Function`
- `ToolFunctionDefinition`
  - `Name`, `Description`, `Parameters`

### インターフェース
- `LLMProvider`
  - `Chat(ctx context.Context, messages []Message, tools []ToolDefinition, model string, options map[string]interface{}) (*LLMResponse, error)`
  - `GetDefaultModel() string`

## 詳細動作
- すべて型定義のみで、実行ロジックは持たない。
- `ToolCall` は 2 系統の表現を同時に持てる。
  - `Function *FunctionCall`: OpenAI 互換形式に近い表現
  - `Name` + `Arguments map[string]interface{}`: 実行しやすい内部表現
- `Message` は text only と multimodal の両方に対応するため、`Media []string` を別フィールドで持つ。
- `ToolCallID` は `role=tool` メッセージでどのツールコールへの応答かを示すために使う。

## 入出力・副作用・永続化
### 入力
- 型定義のみのため、外部入力は持たない。

### 出力
- 型 / インターフェース定義

### 副作用
- なし

### 永続化
- なし。ただし JSON タグにより API 入出力やファイル保存のスキーマとして使われる。

## 依存関係
- 標準ライブラリ: `context`

## エラーハンドリング・制約
- バリデーションロジックは持たない。
- `Arguments` や `Parameters` は `map[string]interface{}` のため、内容の型安全性は利用側に委ねられる。
