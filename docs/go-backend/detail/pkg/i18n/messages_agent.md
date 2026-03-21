# pkg/i18n/messages_agent.go 詳細設計

## 対象ソース
- `pkg/i18n/messages_agent.go`

## 概要
`messages_agent.go` は Agent 実行時の警告・移行通知・レート制限メッセージを英語/日本語で登録する。すべて `init()` から `register()` へ流し込み、`pkg/i18n.T()` / `Tf()` で参照される。

## 責務
- Agent 関連メッセージキー群の `en` / `ja` カタログ登録
- 旧ユーザー管理形式から `users.json` への移行案内文保持
- 警告/レート制限文のローカライズ

## 主要な型・関数・メソッド
- `func init()`
- 登録キー（英日共通）
  - `agent.migration_notice`
  - `agent.context_window_warning`
  - `agent.memory_threshold_warning`
  - `agent.rate_limited`
  - `agent.rate_limited_tool`

## 詳細動作
- `init()` は `register("en", ...)` と `register("ja", ...)` を順に呼ぶ。
- `agent.migration_notice`
  - 旧 `USER.md` から新 `~/.clawdroid/data/users.json` 形式への移行手順を複数行テキスト＋ JSON サンプル付きで案内する。
  - 英語版と日本語版で、サンプルの `memo` 例もそれぞれ `Preferred language: English/Japanese` に分かれる。
- `agent.context_window_warning`
  - コンテキストウィンドウ超過時の警告。
- `agent.memory_threshold_warning`
  - メモリしきい値到達時の警告。
- `agent.rate_limited`, `agent.rate_limited_tool`
  - `%s` プレースホルダ付きメッセージで、`Tf()` 前提。

## 入出力・副作用・永続化
- 入力
  - package 初期化時に埋め込まれた固定文字列
- 出力
  - `messages` グローバル辞書への登録
- 永続化
  - なし
- 副作用
  - `pkg/i18n.messages` の更新

## 依存関係
- `pkg/i18n/i18n.go` の `register()`

## エラーハンドリング・制約
- 文字列はソース埋め込み固定値であり、実行時ロードや検証はない。
- `agent.rate_limited*` は `%s` を要求するため、呼び出し側が format 引数を与えないと不完全な文字列になる。
- 旧ユーザー管理の説明は `~/.clawdroid/data/users.json` 固定で、パス可変性はない。
