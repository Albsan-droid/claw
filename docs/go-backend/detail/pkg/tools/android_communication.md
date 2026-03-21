# android_communication.go 詳細設計

## 対象ソース
- `pkg/tools/android_communication.go`

## 概要
電話・SMS・メール作成に関する Android ツールの入力検証を行う。電話番号とメールアドレスの正規表現検証を提供し、他ファイル (`android_contacts.go`) からも再利用される。

## 責務
- 電話番号・メールアドレスの基本書式検証を行う。
- `dial`, `compose_sms`, `compose_email` の必須パラメータを検証する。
- 通信カテゴリのバリデータを登録する。

## 主要な型・関数・メソッド
### 変数
- `phoneNumberRe`
  - 許可文字: 数字、`+`, `-`, `(`, `)`, 空白, `#`, `*`
- `emailRe`
  - 単純なメールアドレス書式検証用正規表現。

### 関数
- `init()`
  - `dial`, `compose_sms`, `compose_email` を登録する。
- `validatePhoneNumber(phone)`
  - 電話番号書式を検証する。
- `validateEmail(email)`
  - メールアドレス書式を検証する。
- `validateCommunicationParams(action, args)`
  - アクション別に送信用 `params` を構築する。

## 詳細動作
- `dial`
  - `phone_number` 必須。
  - `validatePhoneNumber` に通した値を格納する。
- `compose_sms`
  - `phone_number` 必須。
  - 任意で `message` を追加する。
- `compose_email`
  - `to` 必須。
  - `validateEmail` で検証する。
  - 任意で `subject`, `body` を追加する。

## 入出力・副作用・永続化
### 入力
- `action string`
- `args map[string]interface{}`

### 出力
- 検証済み `params`
- 書式エラー時の `error`

### 副作用
- `init()` によるカテゴリバリデータ登録。
- `phoneNumberRe`, `emailRe` はパッケージスコープ変数として他ファイルから参照される。

### 永続化
- なし。

## 依存関係
- `fmt`
- `regexp`
- `toString`
- `registerCategoryValidator`

## エラーハンドリング・制約
- 電話番号はかなり緩い正規表現で、国番号や桁数の厳密検証は行わない。
- メールアドレス検証も簡易版であり、RFC 完全準拠ではない。
- `compose_sms` の `message`、`compose_email` の `subject`/`body` は任意。
- 通話発信や送信確定は行わず、ここでは入力整形のみを担当する。
