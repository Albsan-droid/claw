# android_clipboard.go 詳細設計

## 対象ソース
- `pkg/tools/android_clipboard.go`

## 概要
Android ツールのクリップボード関連アクションに対する最小限の入力検証を行う。コピー時の文字列必須チェックのみを持つシンプルなカテゴリ実装である。

## 責務
- `clipboard_copy`, `clipboard_read` をカテゴリバリデータへ登録する。
- `clipboard_copy` で `text` 必須制約を適用する。

## 主要な型・関数・メソッド
- `init()`
  - クリップボード系アクションを登録する。
- `validateClipboardParams(action, args)`
  - アクション別の `params` を返す。

## 詳細動作
- `clipboard_copy`
  - `args["text"]` を `toString` で取得する。
  - 空文字列ならエラー。
  - 非空なら `params["text"]` に格納する。
- `clipboard_read`
  - パラメータなし。

## 入出力・副作用・永続化
### 入力
- `action string`
- `args map[string]interface{}`

### 出力
- `params map[string]interface{}` または `error`

### 副作用
- パッケージ初期化時にカテゴリバリデータを登録する。

### 永続化
- なし。
- 実際のクリップボード読み書きは Android 側で行われる。

## 依存関係
- `fmt`
- `toString`
- `registerCategoryValidator`

## エラーハンドリング・制約
- `clipboard_copy` の `text` は空文字列を許可しない。
- `clipboard_read` は追加オプションを受け付けない。
- 文字列長や文字種の制限は実装していない。
