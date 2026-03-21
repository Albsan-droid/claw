# android_device_control.go 詳細設計

## 対象ソース
- `pkg/tools/android_device_control.go`

## 概要
端末制御系アクションの入力検証を行う。ライト、音量、マナーモード、DND、輝度の各操作に対し、真偽値・列挙値・整数範囲の制約を適用する。

## 責務
- 端末制御カテゴリのアクションをバリデータへ登録する。
- ブール値・列挙値・範囲付き整数を検証し、Android 側へ送る `params` を構築する。

## 主要な型・関数・メソッド
- `init()`
  - `flashlight`, `set_volume`, `set_ringer_mode`, `set_dnd`, `set_brightness` を登録する。
- `validateDeviceControlParams(action, args)`
  - 各アクションの入力検証を行う。

## 詳細動作
- `flashlight`
  - `enabled` を必須の真偽値とする。
- `set_volume`
  - `stream` 必須。
  - 許可値は `music`, `ring`, `notification`, `alarm`, `system`。
  - `level` は非負整数必須。
- `set_ringer_mode`
  - `mode` 必須。
  - 許可値は `normal`, `vibrate`, `silent`。
- `set_dnd`
  - `enabled` を必須の真偽値とする。
- `set_brightness`
  - `level` は 0〜255 の整数必須。
  - `auto` は任意の真偽値。

## 入出力・副作用・永続化
### 入力
- `action string`
- `args map[string]interface{}`

### 出力
- 正常時: `params`
- 異常時: `error`

### 副作用
- `init()` によるカテゴリバリデータ登録のみ。

### 永続化
- なし。

## 依存関係
- `fmt`
- `toBool`, `toString`, `toInt`
- `registerCategoryValidator`

## エラーハンドリング・制約
- `set_volume` の `level` 上限はこのファイルでは確認しない。端末ごとの最大値は Android 側依存。
- `set_brightness` のみ明示的に 0〜255 に制限する。
- `auto=true` の場合でも `level` は必須で、入力仕様上は省略できない。
- 列挙値外の文字列はすべてエラーにする。
