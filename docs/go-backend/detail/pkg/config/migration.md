# pkg/config/migration.go 詳細設計

## 対象ソース
- `pkg/config/migration.go`

## 概要
`migration.go` は設定ファイルのスキーマバージョン管理を担当する。旧版 `config.json` を現行 `ConfigVersion` に引き上げるための段階的 migration 関数群と、旧 `disabled_actions` から新しい Android カテゴリ構造への変換ロジックを持つ。

## 責務
- 現行スキーマ版数の定義
- `Config.Version` に応じた逐次 migration 実行
- 旧フィールドから新フィールドへの値移送
- Android action 単位の無効化反映

## 主要な型・関数・メソッド
- `const ConfigVersion = 4`
- `func migrateConfig(cfg *Config) bool`
- `func migrateV0ToV1(cfg *Config)`
- `func migrateV1ToV2(cfg *Config)`
- `func migrateV2ToV3(cfg *Config)`
- `func migrateV3ToV4(cfg *Config)`
- `func disableActions(cfg *AndroidToolsConfig, disabled map[string]bool)`

## 詳細動作
### 1. `migrateConfig(cfg)`
- `cfg.Version >= ConfigVersion` の場合は何もしないで `false` を返す。
- migration 関数配列を `cfg.Version` から順に実行する。
  - index 0 → `migrateV0ToV1`
  - index 1 → `migrateV1ToV2`
  - index 2 → `migrateV2ToV3`
  - index 3 → `migrateV3ToV4`
- 実行後は `cfg.Version = ConfigVersion` をセットし、`true` を返す。呼び出し元 (`LoadConfig`) はこれを契機に再保存する。

### 2. 各 migration の内容
- `migrateV0ToV1(cfg)`
  - 実処理なし。
  - コメント上は `queue_messages` を Go ゼロ値 `false` のまま新規書き出しする意図。
- `migrateV1ToV2(cfg)`
  - `cfg.Agents.Defaults.ShowErrors = true`
  - `cfg.Agents.Defaults.ShowWarnings = true`
- `migrateV2ToV3(cfg)`
  - `DefaultAndroidToolsConfig()` をベースに新形式 `AndroidToolsConfig` を構築する。
  - 旧 `cfg.Tools.Android.Enabled` だけは保持する。
  - 旧 `cfg.Tools.Android.DisabledActions []string` を `map[string]bool` に変換し、`disableActions()` で action ごとに `false` へ落とし込む。
  - 変換後は `def.DisabledActions = nil` とし、`cfg.Tools.Android = def` で置換する。
- `migrateV3ToV4(cfg)`
  - `DefaultAndroidToolsConfig()` から `App`, `UI`, `Intent` カテゴリを取り出し、既存 `cfg.Tools.Android` に追加する。
  - 既存 action/他カテゴリは維持しつつ、新規カテゴリトグルのみ補完する。

### 3. `disableActions()`
- 旧 action 名文字列を個別に判定し、該当する `cfg.<Category>.Actions.<Field>` を `false` にする。
- 対応カテゴリ:
  - Alarm: `set_alarm`, `set_timer`, `dismiss_alarm`, `show_alarms`
  - Calendar: `create_event`, `query_events`, `update_event`, `delete_event`, `list_calendars`, `add_reminder`
  - Contacts: `search_contacts`, `get_contact_detail`, `add_contact`
  - Communication: `dial`, `compose_sms`, `compose_email`
  - Media: `media_play_pause`, `media_next`, `media_previous`, `play_music_search`
  - Navigation: `navigate`, `search_nearby`, `show_map`, `get_current_location`
  - Device Control: `flashlight`, `set_volume`, `set_ringer_mode`, `set_dnd`, `set_brightness`
  - Settings: `open_settings`
  - Web: `open_url`, `web_search`
  - Clipboard: `clipboard_copy`, `clipboard_read`

## 入出力・副作用・永続化
- 入力
  - `*Config` の `Version` と既存フィールド値
- 出力
  - 同一インスタンス `cfg` を破壊的に更新
  - `migrateConfig()` の戻り値で「再保存が必要か」を通知
- 永続化
  - 本ファイル単体では保存しない。`pkg/config.LoadConfig()` が `true` 戻り値を見て設定ファイルを再保存する。

## 依存関係
- `pkg/config/config.go`
  - `Config`
  - `AndroidToolsConfig`
  - `DefaultAndroidToolsConfig()`

## エラーハンドリング・制約
- migration 関数群はエラーを返さない設計で、失敗通知経路はない。
- `cfg.Version` が異常に大きい場合は migration を実行せず `false` になる。
- `migrations` 配列長より大きい version を扱う防御として `i < len(migrations)` を併用している。
- `disableActions()` はハードコード文字列の表引きであり、未知の action 名は無視される。
