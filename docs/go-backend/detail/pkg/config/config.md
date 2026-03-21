# pkg/config/config.go 詳細設計

## 対象ソース
- `pkg/config/config.go`

## 概要
`config.go` は Go バックエンド全体で共有する設定スキーマ、デフォルト値、ロード/保存処理、環境変数上書き、ホームディレクトリ展開、Android ツール既定値を定義する。`Config` はランタイムで共有されるため、内部に `sync.RWMutex` を持つ。

## 責務
- 設定構造体群の定義
- JSON / 環境変数 (`env` タグ) によるロード
- デフォルト構成の生成
- 設定ファイルの保存とディレクトリ作成
- `Config` 共有時のロック API 提供
- Android ツールカテゴリの既定ポリシー定義

## 主要な型・関数・メソッド
### 主要型
- `type FlexibleStringSlice []string`
- `type LLMConfig struct`
- `type Config struct`
- `type AgentsConfig struct`
- `type AgentDefaults struct`
- `type ChannelsConfig struct`
- `type WhatsAppConfig struct`
- `type TelegramConfig struct`
- `type DiscordConfig struct`
- `type SlackConfig struct`
- `type LINEConfig struct`
- `type WebSocketConfig struct`
- `type HeartbeatConfig struct`
- `type RateLimitsConfig struct`
- `type GatewayConfig struct`
- `type BraveConfig struct`
- `type DuckDuckGoConfig struct`
- `type WebToolsConfig struct`
- `type ExecToolsConfig struct`
- `type MCPServerConfig struct`
- Android アクション型
  - `AppActions`, `UIActions`, `IntentActions`, `AlarmActions`, `CalendarActions`, `ContactsActions`, `CommunicationActions`, `MediaActions`, `NavigationActions`, `DeviceControlActions`, `SettingsActions`, `WebActions`, `ClipboardActions`
- Android カテゴリ型
  - `AppCategory`, `UICategory`, `IntentCategory`, `AlarmCategory`, `CalendarCategory`, `ContactsCategory`, `CommunicationCategory`, `MediaCategory`, `NavigationCategory`, `DeviceControlCategory`, `SettingsCategory`, `WebCategory`, `ClipboardCategory`
- `type AndroidToolsConfig struct`
- `type MemoryToolsConfig struct`
- `type ToolsConfig struct`

### 主要関数・メソッド
- `func (f *FlexibleStringSlice) UnmarshalJSON(data []byte) error`
- `func DefaultConfig() *Config`
- `func LoadConfig(path string) (*Config, error)`
- `func SaveConfig(path string, cfg *Config) error`
- `func SaveConfigLocked(path string, cfg *Config) error`
- `func (c *Config) Lock()` / `Unlock()` / `RLock()` / `RUnlock()`
- `func (c *Config) CopyFrom(src *Config)`
- `func (c *Config) WorkspacePath() string`
- `func (c *Config) DataPath() string`
- `func DefaultAndroidToolsConfig() AndroidToolsConfig`
- `func expandHome(path string) string`

## 詳細動作
### 1. `FlexibleStringSlice`
- `UnmarshalJSON()` は `[]string` を優先して解釈する。
- 失敗時は `[]interface{}` として再解析し、各要素を文字列へ変換する。
  - `string` はそのまま保持
  - `float64` は `fmt.Sprintf("%.0f", val)` で整数風文字列へ変換
  - その他型は `fmt.Sprintf("%v", val)`
- 目的は `allow_from` のようなフィールドで `123` と `"123"` を同居させること。

### 2. 設定スキーマ
- `Config` は以下をトップレベルに持つ。
  - `Version`
  - `LLM`
  - `Agents`
  - `Channels`
  - `Gateway`
  - `Tools`
  - `Heartbeat`
  - `RateLimits`
- `Config.mu sync.RWMutex` は JSON 非公開フィールドで、ランタイム共有時のみ使う。
- 各構造体には `json` / `label` / `env` タグが付いており、`pkg/gateway/schema.go` が `label` と `json` を反射利用する。

### 3. `DefaultConfig()`
- `Version` は `ConfigVersion` を設定する。
- 主な既定値:
  - `Agents.Defaults.Workspace = "~/.clawdroid/workspace"`
  - `Agents.Defaults.DataDir = "~/.clawdroid/data"`
  - `Agents.Defaults.Temperature = 0`
  - `RestrictToWorkspace = true`
  - `MaxTokens = 8192`
  - `ContextWindow = 128000`
  - `MaxToolIterations = 10`
  - `QueueMessages = false`
  - `ShowErrors = true`
  - `ShowWarnings = true`
  - `Channels.WebSocket.Enabled = true`
  - `Channels.WebSocket.Host = "127.0.0.1"`
  - `Channels.WebSocket.Port = 18793`
  - `Channels.WebSocket.Path = "/ws"`
  - `Gateway.Port = 18790`
  - `Tools.Exec.Enabled = false`
  - `Tools.Memory.Enabled = true`
  - `Tools.Web.Brave.Enabled = false`
  - `Tools.Web.DuckDuckGo.Enabled = true`
  - `Heartbeat.Enabled = true`
  - `Heartbeat.Interval = 30`
  - `RateLimits.MaxToolCallsPerMinute = 30`
  - `RateLimits.MaxRequestsPerMinute = 15`
- `Tools.Android` は `DefaultAndroidToolsConfig()` の戻り値を使用する。

### 4. `LoadConfig(path)`
- `DefaultConfig()` を起点にするため、設定ファイルに存在しない項目は既定値が残る。
- `os.ReadFile(path)` で読み込み、ファイル不存在 (`os.IsNotExist`) の場合はエラー扱いせず既定値を返す。
- 読み込み後に `cfg.Version = 0` としてから `json.Unmarshal` するため、JSON に `version` が無い旧設定は version 0 扱いになる。
- 設定ファイルが存在する場合のみ、その後で `env.Parse(cfg)` を実行し、`CLAWDROID_*` 環境変数で上書きする。`config.json` が無い setup 状態では `LoadConfig()` が既定値を即返すため、env override は適用されない。
- `migrateConfig(cfg)` が `true` を返した場合は `_ = saveConfigLocked(path, cfg)` により自動再保存する。

### 5. 保存処理
- `SaveConfig()` は `cfg.mu.RLock()` を取得してから `saveConfigLocked()` を呼ぶ。
- `SaveConfigLocked()` はロックを取得しない。外部で排他済みの場面（例: Gateway 更新処理）向け。
- `saveConfigLocked()` は `json.MarshalIndent(cfg, "", "  ")` で整形し、親ディレクトリを `os.MkdirAll(dir, 0755)` で作成したうえで `os.WriteFile(path, data, 0600)` する。

### 6. ランタイム共有 API
- `Lock/Unlock/RLock/RUnlock` は `Config.mu` の薄いラッパ。
- `CopyFrom(src)` はトップレベル各フィールドを個別代入する。`src` 側のロックは取らないため、呼び出し元が整合性を担保する。
- `WorkspacePath()` / `DataPath()` は read lock を取り、`expandHome()` で `~` を実パスへ展開して返す。

### 7. `DefaultAndroidToolsConfig()`
- 各 `*Actions` を「全 action=true」で構築する。
- そのうえでカテゴリ既定値を設定し、プライバシー寄りカテゴリのみ抑制する。
  - `Contacts.Enabled = false`
  - `Communication.Enabled = false`
- 他カテゴリ（`App`, `UI`, `Intent`, `Alarm`, `Calendar`, `Media`, `Navigation`, `DeviceControl`, `Settings`, `Web`, `Clipboard`）は `Enabled = true`。

### 8. `expandHome()`
- 空文字はそのまま返す。
- 先頭が `~` の場合のみ `os.UserHomeDir()` の結果で置換する。
- `~/path` 形式は `home + path[1:]` に変換し、`~` 単独はホームディレクトリそのものにする。

## 入出力・副作用・永続化
- 入力
  - JSON 設定ファイル
  - `CLAWDROID_*` 環境変数（設定ファイル存在時に適用）
- 出力
  - `Config` 構造体インスタンス
- 永続化
  - `SaveConfig*()` は指定パスに JSON を 0600 で保存
  - 親ディレクトリは 0755 で自動生成
- 副作用
  - `LoadConfig()` は migration 発生時に設定ファイルを自動再保存する

## 依存関係
- 標準ライブラリ: `encoding/json`, `fmt`, `os`, `path/filepath`, `sync`
- 環境変数パーサ: `github.com/caarlos0/env/v11`
- バージョン移行: `pkg/config/migration.go` の `migrateConfig()` / `ConfigVersion`
- Schema UI: `pkg/gateway/schema.go` が `json` / `label` タグを利用

## エラーハンドリング・制約
- `LoadConfig()` はファイル不存在を正常系として扱うが、JSON パース失敗や `env.Parse` 失敗はそのまま返す。
- ただしファイル不存在時は `env.Parse` まで進まないため、環境変数だけで setup 状態を上書きすることはできない。
- migration 後の自動再保存エラーは無視される（`_ = saveConfigLocked(...)`）。
- `CopyFrom()` は浅いフィールドコピーであり、呼び出し元が `c` の write lock を保持している前提。
- `SaveConfig()` は read lock で marshal するため、同時書き込みを避けるには上位層で `Lock()` と `SaveConfigLocked()` を組み合わせる必要がある。
- `expandHome()` は `~user` 形式を扱わない。
