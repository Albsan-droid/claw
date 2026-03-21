# android_contacts.go 詳細設計

## 対象ソース
- `pkg/tools/android_contacts.go`

## 概要
連絡先検索・詳細取得・追加に関する Android ツールの入力検証を行う。連絡先追加時には `android_communication.go` で定義された電話番号・メールアドレス正規表現を再利用する。

## 責務
- `search_contacts`, `get_contact_detail`, `add_contact` をカテゴリバリデータへ登録する。
- 連絡先操作に必要な必須パラメータを検証する。
- `add_contact` 時の電話番号・メールアドレス書式を確認する。

## 主要な型・関数・メソッド
- `init()`
  - 連絡先系 3 アクションを登録する。
- `validateContactsParams(action, args)`
  - アクション別に `params` を構築する。

## 詳細動作
- `search_contacts`
  - `query` 必須。
- `get_contact_detail`
  - `contact_id` 必須。
- `add_contact`
  - `name` 必須。
  - 任意の `phone` があれば `phoneNumberRe` で検証する。
  - 任意の `email` があれば `emailRe` で検証する。
  - 検証済みの値だけを `params` に含める。

## 入出力・副作用・永続化
### 入力
- `action string`
- `args map[string]interface{}`

### 出力
- `params map[string]interface{}`
- 検証エラー時の `error`

### 副作用
- `init()` によりカテゴリバリデータ表へ登録する。

### 永続化
- なし。
- 連絡先の実保存は Android 側処理が担う。

## 依存関係
- `fmt`
- `toString`
- `registerCategoryValidator`
- `phoneNumberRe`, `emailRe`
  - `android_communication.go` で定義された正規表現を利用する。

## エラーハンドリング・制約
- `add_contact` では `name` が空だとエラー。
- `phone` と `email` は任意だが、指定された場合は正規表現に合致しないとエラー。
- 重複連絡先の確認、必須項目の追加制約、名前長などは検証しない。
