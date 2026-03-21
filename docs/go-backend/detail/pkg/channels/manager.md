# manager.go 詳細設計

## 対象ソース
- `pkg/channels/manager.go`

## 概要
利用可能なチャネル実装を束ねるオーケストレータ。設定に応じたチャネル生成、起動・停止、OutboundMessage の配送、状態問い合わせを担当する。

## 責務
- 有効チャネルの初期化
- 全チャネルのライフサイクル管理
- メッセージバス outbound 側の購読と配送
- チャネル登録状態の照会/動的更新

## 主要な型・関数・メソッド
### `type Manager struct`
- `channels map[string]Channel`
- `bus *bus.MessageBus`
- `config *config.Config`
- `configPath string`
- `dispatchTask *asyncTask`
- `mu sync.RWMutex`

### `type asyncTask struct`
- `cancel context.CancelFunc`

### `NewManager(cfg, messageBus, configPath) (*Manager, error)`
- `Manager` を作成し、`initChannels` を呼んだ結果を返す。
- 呼び出し側は `error` を確認する前提だが、現実装の `initChannels()` は最終的に `nil` を返すため、失敗は主に将来的な拡張余地またはシグネチャ上の契約として存在する。

### `initChannels() error`
- Telegram / WhatsApp / Discord / Slack / LINE / WebSocket を順に判定・生成する。
- 各チャネルごとに `Enabled` と必須設定値を見て初期化を試みる。
- 個別初期化失敗はログに残すが、他チャネル初期化は継続する。
- 最終的には常に `nil` を返す実装になっている。

### `StartAll(ctx)`
- dispatch 用コンテキストを派生させ、`dispatchOutbound` を goroutine 起動する。
- すべての登録チャネルに対して `Start(ctx)` を呼ぶ。
- 個別チャネル開始失敗はログのみで継続する。

### `StopAll(ctx)`
- dispatch goroutine を cancel する。
- すべての登録チャネルに `Stop(ctx)` を呼ぶ。
- 個別停止失敗はログのみで継続する。

### `dispatchOutbound(ctx)`
- ループで `m.bus.SubscribeOutbound(ctx)` を購読する。
- 内部チャネルは無視する。
- `msg.Type == "status"` かつ `Channel != "websocket"` の場合は配送しない。
- 対象チャネルを map から取得し、`channel.Send(ctx, msg)` する。

### 問い合わせ/更新系
- `GetChannel(name)`
- `GetStatus()`
- `GetEnabledChannels()`
- `RegisterChannel(name, channel)`
- `UnregisterChannel(name)`
- `SendToChannel(ctx, channelName, chatID, content)`

## 詳細動作
### 初期化
- Telegram: `Enabled && Token != ""`
- WhatsApp: `Enabled && BridgeURL != ""`
- Discord: `Enabled && Token != ""`
- Slack: `Enabled && BotToken != ""`
- LINE: `Enabled && ChannelAccessToken != ""`
- WebSocket: `Enabled`

各条件を満たしたものだけ `NewXxxChannel` を呼ぶ。失敗してもプロセス全体は止めず、利用可能なチャネルのみで継続する。

### 起動時配送タスク
- `dispatchOutbound` は `StartAll` で 1 本だけ開始される想定。
- `SubscribeOutbound` が `ctx.Done()` により `ok=false` を返した場合、外側ループが継続し次反復で `ctx.Done()` を検出して終了する。

### 送信ルール
- 内部チャネル (`cli`, `system`, `subagent`) には外部送信しない。
- `status` 型メッセージは WebSocket 専用と見なし、それ以外のチャネル宛なら捨てる。
- 宛先チャネル不明時は Warning ログのみで継続する。

## 入出力・副作用・永続化
### 入力
- `config.Config`
- `MessageBus` からの outbound メッセージ
- チャネル名、chatID、送信本文

### 出力
- 各チャネルの `Start/Stop/Send` 呼び出し
- チャネル状態 map やチャネル名一覧

### 副作用
- goroutine 起動/停止
- 各チャネルインスタンス生成
- ログ出力
- `channels` map 更新

### 永続化
- 永続化なし
- `configPath` は WebSocket 初期化引数として保持するのみ

## 依存関係
- `context`, `fmt`, `sync`
- `pkg/bus`
- `pkg/config`
- `pkg/constants`
- `pkg/logger`
- 同一パッケージの各チャネル実装

## エラーハンドリング・制約
- `initChannels` は個別失敗を返さずログに留めるため、呼び出し側は「一部チャネル未初期化」をエラーとして検知しない。
- `StartAll` / `StopAll` も個別失敗を集約せず、最終的には `nil` を返す。
- `SendToChannel` のみ、対象チャネル不存在時に `error` を返す。
- `channels` map は `RWMutex` で保護される。
- 同時に複数回 `StartAll` が呼ばれた場合の重複 dispatcher 防止は実装されていない。
