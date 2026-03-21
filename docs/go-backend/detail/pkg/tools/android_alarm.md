# android_alarm.go 詳細設計

## 対象ソース
- `pkg/tools/android_alarm.go`

## 概要
Android ツールのアラーム系アクションに対する入力検証を担当する。`init()` でアクション名を共通バリデータへ登録し、`set_alarm` や `set_timer` の範囲制約を適用する。

## 責務
- アラームカテゴリのアクションを `registerCategoryValidator` に登録する。
- アラーム・タイマー関連パラメータを検証し、送信用 `params` を構築する。

## 主要な型・関数・メソッド
- `init()`
  - `set_alarm`, `set_timer`, `dismiss_alarm`, `show_alarms` を登録する。
- `validateAlarmParams(action, args)`
  - アクション別に検証済み `map[string]interface{}` を返す。

## 詳細動作
- `set_alarm`
  - `hour`, `minute` を `toInt` で取得する。
  - `hour` は 0〜23、`minute` は 0〜59 のみ許可する。
  - 任意で `message`, `days`, `skip_ui` を格納する。
- `set_timer`
  - `duration_seconds` を整数として取得し、1〜86400 の範囲のみ許可する。
  - 任意で `message`, `skip_ui` を格納する。
- `dismiss_alarm`
  - パラメータなし。
- `show_alarms`
  - パラメータなし。

## 入出力・副作用・永続化
### 入力
- `action string`
- `args map[string]interface{}`

### 出力
- 正常時: Android 側へ送る `params` マップ
- 異常時: `error`

### 副作用
- `init()` によりグローバルなカテゴリバリデータ表へ登録する。

### 永続化
- なし。

## 依存関係
- `fmt`
  - エラーメッセージ生成に使用する。
- `toInt`, `toString`, `toBool`
  - 同一 `tools` パッケージ内の補助関数に依存する。
- `registerCategoryValidator`
  - `android.go` 側の登録機構に依存する。

## エラーハンドリング・制約
- `set_alarm` は `hour`/`minute` が欠落していてもエラー。
- `set_timer` は `duration_seconds` が欠落、非整数、範囲外のいずれでもエラー。
- `days` の書式検証は本ファイルでは行わず、文字列ならそのまま通す。
- 未知アクションはこの関数内では明示的に弾かず、呼び出し元の登録経路で制御される前提。
