# pkg/tools/memory.go 詳細設計

## 対象ソース
- `pkg/tools/memory.go`

## 概要
長期記憶と当日メモの読み書きを抽象化したツールである。実際の保存先は `MemoryWriter` 実装へ委譲し、本ファイルはツールインターフェース化とアクション分岐のみを担当する。

## 責務
- 長期記憶の上書き保存を提供する。
- 当日メモへの追記を提供する。
- 長期記憶・当日メモの読み出しを提供する。
- ツール引数の検証と操作種別の分岐を行う。

## 主要な型・関数・メソッド
### `type MemoryWriter interface`
- `WriteLongTerm(content string) error`
- `AppendToday(content string) error`
- `ReadLongTerm() string`
- `ReadToday() string`

### `type MemoryTool struct`
- フィールド: `writer MemoryWriter`
- `NewMemoryTool(writer MemoryWriter) *MemoryTool`
- `Execute(ctx, args) *ToolResult`

## 詳細動作
- `action` は `write_long_term`, `append_daily`, `read_long_term`, `read_daily` の 4 種のみ受け付ける。
- `write_long_term` / `append_daily` では `content` が空文字でも不許可とし、対応メソッドを呼ぶ。
- `read_long_term` / `read_daily` はストアから文字列を取得し、空なら「記憶なし」の固定文言を返す。
- すべて `SilentResult` を返すため、通常はユーザーへ直接表示せず LLM 文脈へ取り込む用途に寄せている。

## 入出力・副作用・永続化
- 入力: `action`, `content`、`MemoryWriter` 実装。
- 出力: 無言成功結果、読み出し結果、またはエラー結果。
- 副作用: `MemoryWriter` 実装に応じたファイル/DB 等への読み書き。
- 永続化: 実装先次第。本ファイル自身は永続層を持たない。

## 依存関係
- 標準ライブラリ: `context`, `fmt`
- 同一パッケージ: `SilentResult`, `ErrorResult`
- 実装想定: コメント上は `agent.MemoryStore`

## エラーハンドリング・制約
- 未知の `action` はエラー。
- 書き込み系で `content` が空の場合はエラー。
- `MemoryWriter` が `nil` の場合の防御コードはなく、呼び出し側で注入保証が必要である。
