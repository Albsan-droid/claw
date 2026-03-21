# pkg/tools/toolloop.go 詳細設計

## 対象ソース
- `pkg/tools/toolloop.go`

## 概要
LLM 応答とツール呼び出しを反復実行するコアループを提供する。メインエージェントとサブエージェントの双方から再利用され、LLM がツール呼び出しを返す限り会話履歴を更新しながら反復する。

## 責務
- ツール定義を LLM プロバイダー形式へ変換して渡す。
- LLM 応答に含まれるツール呼び出しを逐次実行する。
- アシスタントメッセージとツール結果メッセージを会話履歴へ追加する。
- 最大反復回数でループを打ち切る。
- 実行状況を構造化ログで記録する。

## 主要な型・関数・メソッド
### `type ToolLoopConfig struct`
- `Provider providers.LLMProvider`
- `Model string`
- `Tools *ToolRegistry`
- `MaxIterations int`
- `LLMOptions map[string]any`

### `type ToolLoopResult struct`
- `Content string`
- `Iterations int`

### `func RunToolLoop(...) (*ToolLoopResult, error)`
- 引数: `context.Context`, `ToolLoopConfig`, `[]providers.Message`, `channel`, `chatID`
- 戻り値: 最終応答本文と実行イテレーション数

## 詳細動作
1. `iteration < MaxIterations` の間ループする。
2. `ToolRegistry.ToProviderDefs()` で LLM に渡すツール定義を作る。`Tools == nil` なら空配列相当。
3. `LLMOptions` が未指定なら `max_tokens=4096` を設定する。
4. `Provider.Chat(...)` を呼び、LLM 応答を得る。
5. `ToolCalls` が空ならその `Content` を最終結果として終了する。
6. ツール呼び出しがある場合は、LLM の応答内容と tool_calls を `assistant` メッセージとして履歴へ追加する。
7. 各ツール呼び出しについて `ToolRegistry.ExecuteWithContext(...)` を呼ぶ。非同期コールバックは常に `nil` で、サブエージェント側は独立実行前提である。
8. `ToolResult.ForLLM` を優先し、空かつ `Err != nil` の場合のみエラー文字列を補って `tool` メッセージとして履歴へ追加する。
9. 反復終了後、最終本文と反復回数を返す。

## 入出力・副作用・永続化
- 入力: 既存会話履歴、LLM プロバイダー、モデル名、ツールレジストリ、チャネル文脈。
- 出力: `ToolLoopResult` またはエラー。
- 副作用: `pkg/logger` へのログ出力、ツール実行による各種副作用。
- 永続化: なし。履歴は呼び出し中のメモリのみ。

## 依存関係
- 標準ライブラリ: `context`, `encoding/json`, `fmt`
- 同一パッケージ: `ToolRegistry`, `ToolResult`, `ErrorResult`
- 他パッケージ: `pkg/logger`, `pkg/providers`, `pkg/utils`

## エラーハンドリング・制約
- LLM 呼び出し失敗時は `LLM call failed: ...` として即終了する。
- 最大反復数に達してもツール呼び出しが続く場合、追加警告なくその時点で抜けるため、`finalContent` が空のまま返る可能性がある。
- ツール実行結果の `ForUser` はこのループでは扱わず、ユーザー通知の責務は外側にある。
