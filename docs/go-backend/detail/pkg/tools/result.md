# pkg/tools/result.go 詳細設計

## 対象ソース
- `pkg/tools/result.go`

## 概要
ツール実行結果の標準表現を定義する。LLM に返す文脈、ユーザーに直接表示する文面、非同期フラグ、エラーフラグ、メディア添付、内部エラーを 1 つの構造体に集約し、全ツールの戻り値の意味を統一する。

## 責務
- ツールの成功・失敗・非同期開始・無言実行を共通表現にまとめる。
- LLM 向けの説明 (`ForLLM`) とユーザー表示 (`ForUser`) を分離する。
- JSON シリアライズ時に内部エラー `Err` を除外する。
- よく使う結果生成をファクトリ関数で簡略化する。

## 主要な型・関数・メソッド
### `type ToolResult struct`
- `ForLLM string`: LLM に会話文脈として返す本文。
- `ForUser string`: 利用者へ直接送る本文。空なら送信しない。
- `Silent bool`: true の場合はユーザー通知を抑制する。
- `IsError bool`: ツール失敗であることを示す。
- `Async bool`: バックグラウンド実行中であることを示す。
- `Media []string`: data URL 形式のメディア添付。
- `Err error`: 内部ログ・制御用の元エラー。JSON 出力対象外。

### ファクトリ関数
- `NewToolResult(forLLM string) *ToolResult`
- `SilentResult(forLLM string) *ToolResult`
- `AsyncResult(forLLM string) *ToolResult`
- `ErrorResult(message string) *ToolResult`
- `UserResult(content string) *ToolResult`

### メソッド
- `MarshalJSON() ([]byte, error)`: `Err` を除外した JSON を返す。
- `WithError(err error) *ToolResult`: `Err` を設定して自身を返すチェーン用補助。

## 詳細動作
- 全結果で `ForLLM` が中心となる。`toolloop.go` はツール結果を LLM へ返す際、まず `ForLLM` を参照し、空なら `Err` の内容を補う。
- `SilentResult` はファイル操作や状態更新のように、ユーザーへ逐一見せたくない操作向けである。
- `AsyncResult` は完了前にエージェントループへ即返却する用途を想定する。
- `ErrorResult` は `IsError=true` を立てるが、内部 `Err` は必要に応じて `WithError` で別途保持する。
- `UserResult` は LLM と利用者に同一文面を返したい場面向けで、CLI 的な結果表示に向く。

## 入出力・副作用・永続化
- 入力: ツール実行結果本文、エラー、メディア data URL。
- 出力: `*ToolResult`、または JSON バイト列。
- 副作用: なし。
- 永続化: なし。

## 依存関係
- 標準ライブラリ: `encoding/json`
- 利用側: `registry.go`, `toolloop.go`, 個別ツール全般

## エラーハンドリング・制約
- `MarshalJSON` 自体の失敗は `encoding/json` に依存する。
- `ForLLM` が空のまま返ると利用側で情報不足になり得るため、ツール実装側で最低限の文面を持たせる設計が前提となる。
- `Err` は JSON に出ないため、外部 API 応答だけでは内部原因を復元できない。
