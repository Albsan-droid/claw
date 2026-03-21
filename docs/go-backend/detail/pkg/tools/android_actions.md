# android_actions.go 詳細設計

## 対象ソース
- `pkg/tools/android_actions.go`

## 概要
Android ツールで公開する全アクションのメタデータを定義し、設定値とクライアント種別に応じて利用可能アクションを絞り込み、ツール説明文と JSON Schema 風パラメータ定義を動的生成する。

## 責務
- Android ツールの全アクション一覧をコード上で一元管理する。
- アクション名からカテゴリを引く高速なルックアップ表を構築する。
- UI 専用アクション集合を前計算し、`main` クライアントから隠せるようにする。
- 設定 (`AndroidToolsConfig`) によるカテゴリ単位・アクション単位の有効/無効を判定する。
- 有効アクション一覧から説明文とパラメータ定義を生成する。

## 主要な型・関数・メソッド
### 型
- `androidAction`
  - `Name`, `Category`, `Desc`, `UIOnly`, `Params` を持つアクション定義。
- `androidParam`
  - パラメータ名、型、説明、必須フラグ、列挙値を持つ。

### 主要変数
- `allActions`
  - Android ツールが扱う全アクションの静的定義。
  - カテゴリは `app`, `ui`, `intent`, `alarm`, `calendar`, `contacts`, `communication`, `media`, `navigation`, `device_control`, `settings`, `web`, `clipboard`。
- `actionCategoryMap`
  - `action name -> category` の逆引き表。
- `uiActionMap`
  - `UIOnly == true` のアクション集合。

### 関数
- `init()`
  - `allActions` を走査し、`actionCategoryMap` と `uiActionMap` を構築する。
- `actionCategory(action)`
  - アクション名からカテゴリ名を返す。未知のアクションでは空文字列。
- `enabledActions(cfg, clientType)`
  - クライアント種別と設定で利用可能なアクションだけを返す。
- `isActionDisabledByConfig(cfg, action)`
  - 個別アクションの有効/無効フラグを `cfg.<Category>.Actions.<Action>` から判定する。
- `isCategoryEnabled(cfg, category)`
  - カテゴリ全体の有効/無効を判定する。
- `buildDescription(actions)`
  - 利用可能アクション一覧を人間向け文字列として整形する。
- `buildParameters(actions)`
  - 利用可能アクション一覧から JSON Schema 風の `properties` を生成する。

## 詳細動作
### 1. アクションカタログ
`allActions` はアクション名・説明・カテゴリ・パラメータ仕様の真実源である。例えば以下を含む。
- アプリ管理: `search_apps`, `app_info`, `launch_app`
- UI 操作: `screenshot`, `get_ui_tree`, `tap`, `swipe`, `text`, `keyevent`
- Intent: `broadcast`, `intent`
- アラーム: `set_alarm`, `set_timer`, `dismiss_alarm`, `show_alarms`
- カレンダー: `create_event`, `query_events`, `update_event`, `delete_event`, `list_calendars`, `add_reminder`
- 連絡先: `search_contacts`, `get_contact_detail`, `add_contact`
- 通信: `dial`, `compose_sms`, `compose_email`
- メディア: `media_play_pause`, `media_next`, `media_previous`, `play_music_search`
- ナビ: `navigate`, `search_nearby`, `show_map`, `get_current_location`
- 端末制御: `flashlight`, `set_volume`, `set_ringer_mode`, `set_dnd`, `set_brightness`
- 設定: `open_settings`
- Web: `open_url`, `web_search`
- クリップボード: `clipboard_copy`, `clipboard_read`

UI 操作系には `UIOnly: true` が付いており、`clientType == "main"` のときは公開対象から除外される。

### 2. 有効アクションの絞り込み
`enabledActions` は各アクションに対して以下を順に適用する。
1. `clientType == "main"` かつ `UIOnly` なら除外。
2. `isCategoryEnabled(cfg, a.Category)` が偽なら除外。
3. `isActionDisabledByConfig(cfg, a.Name)` が真なら除外。
4. 条件をすべて満たしたアクションだけを返却。

### 3. 設定による無効化
`isActionDisabledByConfig` はアクション名を `switch` で分岐し、対応する設定構造体の真偽値を確認する。例えば:
- `set_alarm` → `cfg.Alarm.Actions.SetAlarm`
- `compose_email` → `cfg.Communication.Actions.ComposeEmail`
- `web_search` → `cfg.Web.Actions.WebSearch`

未知アクションは `false` を返すため、この関数単体では無効化されない。最終的な未知判定は別ファイル側で行われる。

### 4. 説明文生成
`buildDescription` は次の形式でプレーンテキストを組み立てる。
- 先頭: `Control the Android device. Available actions:`
- 続く各行: `- <action>: <description>`

### 5. パラメータ定義生成
`buildParameters` は以下の手順でスキーマを作る。
1. `action` プロパティに、有効アクション名の `enum` を設定する。
2. 全アクションの全パラメータを走査し、同名パラメータを `seen` でマージする。
3. 同名パラメータで説明文が異なる場合は `; ` 区切りで連結する。
4. `enum` が定義されているパラメータはそのまま保持する。
5. ルートの `required` は `action` のみで、個々の必須性は説明・メタ情報側に留まる。

## 入出力・副作用・永続化
### 入力
- `config.AndroidToolsConfig`
- `clientType string`
- `[]androidAction`

### 出力
- フィルタ済みアクション配列
- 説明文文字列
- JSON Schema 風 `map[string]interface{}`

### 副作用
- パッケージ初期化時にルックアップ表をメモリ上へ構築する。

### 永続化
- なし。

## 依存関係
- `github.com/KarakuriAgent/clawdroid/pkg/config`
  - 各カテゴリ・各アクションの有効フラグ参照に使用する。
- `strings`
  - 説明文および説明マージ処理に使用する。

## エラーハンドリング・制約
- 本ファイルの主要処理は基本的にエラーを返さない。
- 未知カテゴリに対する `isCategoryEnabled` は `false` を返す。
- 未知アクションに対する `actionCategory` は空文字列、`isActionDisabledByConfig` は `false` を返す。
- `buildParameters` は型整合性の検証を行わず、メタデータ定義をそのまま出力する。
- `TZ` や実行時バリデーションなど、動的な制約は本ファイルでは扱わない。
