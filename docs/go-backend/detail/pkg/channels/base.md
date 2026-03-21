# base.go 詳細設計

## 対象ソース
- `pkg/channels/base.go`

## 概要
全チャネル実装が共通で使う基盤を提供する。チャネル名、設定参照、allowlist 判定、`InboundMessage` 生成と `MessageBus` への投入を共通化する。

## 責務
- `Channel` インターフェース定義
- 共通状態 (`name`, `bus`, `allowList`, `running`) の保持
- allowlist による送信者制御
- `InboundMessage` の標準生成

## 主要な型・関数・メソッド
### `type Channel interface`
各チャネルが満たすべき契約。
- `Name() string`
- `Start(ctx context.Context) error`
- `Stop(ctx context.Context) error`
- `Send(ctx context.Context, msg bus.OutboundMessage) error`
- `IsRunning() bool`
- `IsAllowed(senderID string) bool`

### `type BaseChannel struct`
- `config interface{}`
  - チャネル固有設定を保持するが、本ファイルでは直接解釈しない
- `bus *bus.MessageBus`
  - 共通のメッセージバス
- `running bool`
  - 稼働状態
- `name string`
  - チャネル名
- `allowList []string`
  - 許可された送信者一覧

### `NewBaseChannel(name string, config interface{}, bus *bus.MessageBus, allowList []string) *BaseChannel`
- 共通フィールドを初期化する。

### `Name() string`
- チャネル名を返す。

### `IsRunning() bool`
- `running` を返す。

### `IsAllowed(senderID string) bool`
- allowlist 未設定時は全許可。
- `senderID` が `"id|username"` 形式の場合、ID 部分とユーザー名部分を分解して照合する。
- allowlist 側の各要素について `@` を外した上で比較する。
- 完全一致、ID 部分一致、ユーザー名一致、`id|username` の片側一致を許容する。

### `HandleMessage(senderID, chatID, content string, media []string, metadata map[string]string)`
- allowlist で拒否された場合は何もせず return。
- `sessionKey := fmt.Sprintf("%s:%s", c.name, chatID)` を生成する。
- `bus.InboundMessage` を構築して `c.bus.PublishInbound` に渡す。

### `setRunning(running bool)`
- `running` を更新する内部ヘルパー。

## 詳細動作
- 各チャネル実装は `BaseChannel` を埋め込み、受信イベントを `HandleMessage` に集約する。
- allowlist 判定では Telegram 由来の旧形式との互換性を意識し、複数形式を柔軟に比較している。
- `HandleMessage` はチャネル固有情報を `metadata` としてそのまま流し、本文/メディア/セッションキーのみ標準化する。

## 入出力・副作用・永続化
### 入力
- チャネル設定、チャネル名、allowlist
- 受信イベントの送信者 ID / Chat ID / 本文 / メディア / メタデータ

### 出力
- `Name`, `IsRunning`, `IsAllowed` の戻り値
- `HandleMessage` は戻り値なし

### 副作用
- `MessageBus.PublishInbound` によるメッセージ投入
- `running` 状態変更

### 永続化
- なし

## 依存関係
- `context`
- `fmt`
- `strings`
- `github.com/KarakuriAgent/clawdroid/pkg/bus`

## エラーハンドリング・制約
- `HandleMessage` は `error` を返さないため、バス投入失敗を呼び出し元へ返せない。
- `running` 参照/更新にロックは使っていないため、呼び出し側は必要に応じて外側で整合性を担保する。
- allowlist は完全一致ベースで、部分一致や正規表現はサポートしない。
- `metadata` は `nil` のままでも許容される。

