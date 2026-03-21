# pkg/i18n/messages_config.go 詳細設計

## 対象ソース
- `pkg/i18n/messages_config.go`

## 概要
`messages_config.go` は Config UI 用ラベル辞書を定義する。`pkg/gateway/schema.go` が `label` タグから生成する `config.<label>` キーの表示名を英語/日本語で提供し、設定画面のセクション名・項目名・Android ツールカテゴリ名をローカライズする。

## 責務
- `config.*` 名前空間の翻訳辞書登録
- 英語ラベルの明示登録（`config.` 接頭辞を表示させないため）
- 日本語ラベルの包括登録

## 主要な型・関数・メソッド
- `func init()`
- `func configLabelsEN() map[string]string`
- 主なキー領域
  - トップレベルセクション: `config.LLM`, `config.Agent Defaults`, `config.Tool Settings` など
  - 基本項目: `config.Model`, `config.API Key`, `config.Enabled`, `config.Port` など
  - チャネル項目: `config.WhatsApp`, `config.Telegram`, `config.WebSocket` など
  - Android カテゴリ: `config.App`, `config.UI Automation`, `config.Device Control` など
  - Android action: `config.Search Apps`, `config.Set Alarm`, `config.Open URL` など

## 詳細動作
### 1. `init()`
- `register("en", configLabelsEN())` を呼び、英語ラベルを関数経由でまとめて登録する。
- 続けて `register("ja", map[string]string{...})` で日本語ラベルを大量登録する。
- コメントのとおり、キーはすべて `config.` 名前空間付きで、他カテゴリの翻訳キーと衝突しないようにしている。

### 2. 英語辞書 `configLabelsEN()`
- 値は基本的に `pkg/config/config.go` の `label` タグ文字列と一致する。
- 関数化している理由は、未登録時に `T()` が返してしまう `config.X` 形式を UI に見せないため。
- `map[string]string` として返すため、英語追加時はこの関数へ追記する。

### 3. 日本語辞書
- `init()` 内のインライン map で管理する。
- 対象範囲:
  - トップレベルセクション
  - LLM/Agent/Channels/Gateway/Heartbeat/RateLimits の各項目
  - Web 検索設定
  - Android カテゴリと Android action 一式
- 例:
  - `config.Agent Defaults` → `エージェント設定`
  - `config.Data Directory` → `データディレクトリ`
  - `config.UI Automation` → `UI 操作`
  - `config.Get Current Location` → `現在地取得`

## 入出力・副作用・永続化
- 入力
  - package 初期化時に埋め込まれた固定キー/値
- 出力
  - `pkg/i18n.messages` への `config.*` ラベル登録
- 永続化
  - なし
- 副作用
  - グローバル翻訳辞書更新

## 依存関係
- `pkg/i18n/i18n.go` の `register()`
- 利用側: `pkg/gateway/schema.go` の `i18n.T(locale, "config."+labelTag(...))`
- ラベル源: `pkg/config/config.go` の `label` struct tag

## エラーハンドリング・制約
- `pkg/config` 側の `label` タグ追加時に本辞書を更新しないと、未翻訳時は `config.<label>` がそのまま UI に出る可能性がある。
- キー管理は手書き map のため、`label` タグとの同期はコンパイル時保証されない。
- 英語・日本語の収録範囲は `config.go` 依存で、将来新規カテゴリ追加時は両辞書更新が必要。
