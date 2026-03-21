# android_calendar.go 詳細設計

## 対象ソース
- `pkg/tools/android_calendar.go`

## 概要
Android ツールのカレンダー系アクションに対する入力検証を行う。イベント作成・検索・更新・削除・リマインダ追加の各アクションで必須値を確認し、送信用パラメータを構築する。

## 責務
- カレンダーカテゴリのアクションを共通バリデータ表に登録する。
- カレンダーイベント系パラメータの必須性と型を検証する。
- 呼び出し元で `calendar_id` を注入できる前提の `params` を返す。

## 主要な型・関数・メソッド
- `init()`
  - `create_event`, `query_events`, `update_event`, `delete_event`, `list_calendars`, `add_reminder` を登録する。
- `validateCalendarParams(action, args)`
  - アクション別に検証済みパラメータを返す。

## 詳細動作
- `create_event`
  - `title`, `start_time` を必須とする。
  - 任意で `end_time`, `description`, `location`, `all_day` を設定する。
- `query_events`
  - `start_time` と `end_time` の両方を必須とする。
  - 任意で `query` を設定する。
- `update_event`
  - `event_id` を必須とする。
  - `title`, `start_time`, `end_time`, `description`, `location` のうち、非空文字列だけを更新候補として格納する。
- `delete_event`
  - `event_id` を必須とする。
- `list_calendars`
  - パラメータなし。
- `add_reminder`
  - `event_id` と非負整数の `minutes` を必須とする。

## 入出力・副作用・永続化
### 入力
- `action string`
- `args map[string]interface{}`

### 出力
- 正常時: `params map[string]interface{}`
- 異常時: `error`

### 副作用
- `init()` でカテゴリバリデータへ登録する。

### 永続化
- なし。
- イベントの保存・更新自体は Android 側実装が担当し、このファイルは入力整形のみ行う。

## 依存関係
- `fmt`
- `toString`, `toBool`, `toInt`
- `registerCategoryValidator`

## エラーハンドリング・制約
- 日時文字列は「ISO 8601 形式」を想定した説明になっているが、このファイルでは厳密パースは行わない。
- `minutes` は 0 以上の整数のみ許可する。
- `update_event` は `event_id` 以外の更新項目が空でもエラーにしない。
- `calendar_id` はこのファイルでは扱わず、呼び出し元 (`android.go`) が必要に応じて設定から注入する。
