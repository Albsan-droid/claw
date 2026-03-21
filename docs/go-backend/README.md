# Go バックエンド設計ドキュメント

## スコープ

このディレクトリは **現在の Go バックエンド実装** だけを対象にした設計ドキュメントです。記述対象は `cmd/` と `pkg/` の現行コードであり、移行案・将来構想・Android Kotlin 実装の詳細は扱いません。Android 側については、Go バックエンドから見える接点だけを説明します。

主な起点:

- エントリポイント: `cmd/clawdroid/main.go`
- 中核ランタイム: `pkg/agent/loop.go`
- チャネル管理: `pkg/channels/*.go`
- 設定 API: `pkg/gateway/*.go`
- ツール実行: `pkg/tools/*.go`

## 記述方針

- **コード準拠**: すべて現行ソースを直接読んで記述します。
- **現状記述のみ**: 「こうすべき」ではなく「現在どう動くか」を説明します。
- **出典明記**: 重要な説明にはソースファイルパスと主要シンボル名を添えます。
- **Go バックエンド中心**: Android アプリ詳細は、`WebSocket`・`broadcast`・HTTP Config API などの接点に限定します。

## ドキュメント構成

- `overview/architecture.md` — プロセスモード、ランタイム構成、起動/停止、Android 連携の俯瞰
- `overview/runtime-flows.md` — 起動フロー、メッセージフロー、ツールフロー、Cron/Heartbeat の実行経路
- `overview/interfaces-and-storage.md` — 外部/内部インターフェース、永続化パス、設定と保存形式
- `overview/package-map.md` — `cmd/` / `pkg/` の責務対応表

## 用語・表記の約束

- **プロセスモード** は `cmd/clawdroid/main.go` の `main()` が受け付けるサブコマンド単位で表記します。
- **ランタイムモード** は `gateway` 実行時の内部状態（setup / degraded / full）を指します。
- **チャネル** は `pkg/channels/base.go` の `Channel` 実装を指します。
- **セッションキー** は通常 `channel:chatID` 形式で、`pkg/channels/base.go` の `BaseChannel.HandleMessage()` が生成します。
- **内部チャネル** は `pkg/constants/channels.go` の `cli` / `system` / `subagent` を指します。

## 詳細ドキュメントの配置規約

詳細ドキュメントを追加する場合は、**`cmd/` と `pkg/` のソースツリーをそのまま鏡写し** にし、原則として **`.go` → `.md`** の対応で配置します。`*_test.go` は対象外です。

例:

- `cmd/clawdroid/main.go` → `docs/go-backend/detail/cmd/clawdroid/main.md`
- `pkg/agent/loop.go` → `docs/go-backend/detail/pkg/agent/loop.md`
- `pkg/tools/android.go` → `docs/go-backend/detail/pkg/tools/android.md`

この `overview/` 配下は、その詳細群を横断して読むための概要文書です。
