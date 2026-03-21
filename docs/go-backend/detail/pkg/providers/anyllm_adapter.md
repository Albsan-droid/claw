# pkg/providers/anyllm_adapter.go

## 対象ソース
- `pkg/providers/anyllm_adapter.go`

## 概要
`AnyLLMAdapter` は `any-llm-go` の各プロバイダ実装を `LLMProvider` インターフェースに適合させるアダプタである。内部共通型 `providers.Message` / `ToolDefinition` / `LLMResponse` と、any-llm-go の型を相互変換する。

## 責務
- `provider/model` 形式の設定文字列を分解する
- OpenAI / Anthropic / Gemini 用 provider を生成する
- 内部メッセージを any-llm-go 形式へ変換する
- internal tool schema を any-llm-go tools へ変換する
- any-llm-go のチャット結果を `LLMResponse` へ戻す

## 主要な型・関数・メソッド
### 型
- `AnyLLMAdapter`
  - `provider anyllm.Provider`
  - `defaultModel string`
  - `modelName string`

### 関数・メソッド
- `parseModel(model string) (providerName, modelName string)`
- `NewAnyLLMAdapter(model, apiKey, baseURL string) (*AnyLLMAdapter, error)`
- `createAnyLLMProvider(name, apiKey, baseURL string) (anyllm.Provider, error)`
- `Chat(ctx context.Context, messages []Message, tools []ToolDefinition, model string, options map[string]interface{}) (*LLMResponse, error)`
- `GetDefaultModel() string`
- `convertMessagesToAnyLLM(messages []Message) []anyllm.Message`
- `convertToolsToAnyLLM(tools []ToolDefinition) []anyllm.Tool`
- `convertAnyLLMResult(result *anyllm.ChatCompletion) *LLMResponse`

## 詳細動作
### モデル文字列の解釈
- `parseModel` は最初の `/` だけで分割する。
- `/` が無い場合は `providerName=""`, `modelName=<元文字列>` となり、`NewAnyLLMAdapter` 側でエラー扱いになる。
- エイリアス
  - `claude` -> `anthropic`
  - `google` -> `gemini`

### provider 生成
- `createAnyLLMProvider` は `apiKey` が空でなければ `anyllm.WithAPIKey` を付ける。
- `baseURL` が空でなければ `anyllm.WithBaseURL` を付ける。
- サポートは `anthropic`, `gemini`, `openai` のみ。
- OpenAI 互換サーバーは `openai + baseURL` で使う想定。

### `Chat`
- `CompletionParams.Model` には引数 `model` ではなく **`a.modelName`** を入れる。
- `messages` と `tools` は変換関数経由で any-llm-go 形式にする。
- `options["max_tokens"]` は `int` または `float64` を受け取る。
- `options["temperature"]` は `float64` のときのみ採用する。
- 実際の API 呼び出しは `a.provider.Completion(ctx, params)` に委譲する。

### メッセージ変換
- `ToolCallID != ""` のメッセージは `anyllm.RoleTool` とし、tool result として扱う。
- `Media` がある場合は text part と image_url part を持つ multimodal message を作る。
- `ToolCalls` がある assistant メッセージは `anyllm.ToolCall` 配列に変換する。
  - 名前は `tc.Function.Name` を優先、空なら `tc.Name`
  - 引数は `tc.Function.Arguments` を優先、空なら `tc.Arguments` を JSON 化

### ツール定義変換
- すべて `Type: "function"` として any-llm-go の `Tool` へ写す。

### 応答変換
- `Choices` が空なら空の `LLMResponse` を返す。
- 先頭 `Choices[0]` だけを使う。
- `choice.Message.ContentString()` を `Content` に入れる。
- `ToolCalls` は `tc.Function.Arguments` を `map[string]interface{}` へ `json.Unmarshal` し、内部 `ToolCall` に戻す。
- Usage があれば `UsageInfo` にコピーする。

## 入出力・副作用・永続化
### 入力
- `provider/model` 形式のモデル指定
- API キーと任意の base URL
- `[]Message`, `[]ToolDefinition`, チャットオプション

### 出力
- `*AnyLLMAdapter`
- `*LLMResponse`
- any-llm-go 形式の message / tool 配列

### 副作用
- LLM API へのネットワーク呼び出し
- JSON marshal / unmarshal

### 永続化
- なし

## 依存関係
- `github.com/mozilla-ai/any-llm-go`
- `github.com/mozilla-ai/any-llm-go/providers/anthropic`
- `github.com/mozilla-ai/any-llm-go/providers/gemini`
- `github.com/mozilla-ai/any-llm-go/providers/openai`
- 標準ライブラリ: `context`, `encoding/json`, `fmt`, `strings`

## エラーハンドリング・制約
- モデル文字列に provider 部分が無いとエラー。
- 未対応 provider 名はエラー。
- `convertAnyLLMResult` の引数 JSON unmarshal エラーは無視され、`Arguments` は `nil` または空マップのままになりうる。
- `Chat` の `model` 引数は現実には無視され、アダプタ生成時の `modelName` が使われる。
