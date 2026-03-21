# android_settings.go 詳細設計

## 対象ソース
- `pkg/tools/android_settings.go`

## 概要
Android 設定画面を開くアクション `open_settings` の入力検証を行う。設定セクション文字列を列挙値で制限し、未指定時は `main` を既定値として補う。

## 責務
- `open_settings` をカテゴリバリデータへ登録する。
- 設定セクション名の既定値補完と列挙値チェックを行う。

## 主要な型・関数・メソッド
### 変数
- `validSettingsSections`
  - 許可される設定セクション名の集合。
  - `main`, `wifi`, `bluetooth`, `airplane`, `display`, `sound`, `battery`, `apps`, `location`, `security`, `accessibility`, `date_time`, `language`, `developer`, `about`, `notification`, `mobile_data`, `nfc`, `privacy` を含む。

### 関数
- `init()`
  - `open_settings` を登録する。
- `validateSettingsParams(action, args)`
  - `section` の補完と検証を行う。

## 詳細動作
1. `section := toString(args["section"])` で文字列を取得する。
2. 空文字列なら `section = "main"` を設定する。
3. `validSettingsSections` に存在しない場合は、全許可値をソートしてエラーメッセージへ埋め込む。
4. 正常なら `params["section"] = section` を返す。

## 入出力・副作用・永続化
### 入力
- `action string`
- `args map[string]interface{}`

### 出力
- `params map[string]interface{}`
- 不正セクション時の `error`

### 副作用
- `init()` でカテゴリバリデータを登録する。

### 永続化
- なし。

## 依存関係
- `fmt`
- `sort`
- `strings`
- `toString`
- `registerCategoryValidator`

## エラーハンドリング・制約
- 未知セクションでは、利用可能な全セクション一覧を含む詳細なエラーメッセージを返す。
- `action` 引数自体は関数内で分岐せず、`open_settings` 専用バリデータとして利用される前提。
