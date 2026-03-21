# android_web.go 詳細設計

## 対象ソース
- `pkg/tools/android_web.go`

## 概要
ブラウザ起動と Web 検索に関する Android ツールの入力検証を行う。URL を開く場合は許可スキームを `http` / `https` に限定する。

## 責務
- `open_url`, `web_search` をカテゴリバリデータへ登録する。
- URL スキーム制限を適用する。
- Web 検索クエリの必須性を確認する。

## 主要な型・関数・メソッド
### 変数
- `allowedSchemes`
  - `http`, `https` のみを真にしたマップ。

### 関数
- `init()`
  - Web 系アクションを登録する。
- `validateWebParams(action, args)`
  - アクション別検証を行う。

## 詳細動作
- `open_url`
  1. `url` を必須文字列として取得する。
  2. `strings.SplitN(rawURL, ":", 2)[0]` で先頭スキーム相当部分を抽出する。
  3. 小文字化したスキームが `allowedSchemes` に含まれるか確認する。
  4. 許可されていれば `params["url"]` に格納する。
- `web_search`
  - `query` を必須文字列として検証し、`params["query"]` に格納する。

## 入出力・副作用・永続化
### 入力
- `action string`
- `args map[string]interface{}`

### 出力
- `params` または `error`

### 副作用
- `init()` によるカテゴリバリデータ登録。

### 永続化
- なし。

## 依存関係
- `fmt`
- `strings`
- `toString`
- `registerCategoryValidator`

## エラーハンドリング・制約
- `open_url` は `http` / `https` 以外のスキームを拒否する。
- スキーム抽出は単純な `:` 分割であり、URL 全体の妥当性検証までは行わない。
- `web_search` は空クエリを許可しない。
