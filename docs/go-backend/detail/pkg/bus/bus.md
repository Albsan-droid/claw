# bus.go 詳細設計

## 対象ソース
- `pkg/bus/bus.go`

## 概要
`MessageBus` は、各チャネル実装とバックエンド内部処理の間でメッセージを受け渡すための軽量なインメモリバスである。受信方向(`inbound`)と送信方向(`outbound`)を別々の Go channel で保持し、加えてチャネル名ごとの `MessageHandler` 登録領域を持つ。

## 責務
- 受信メッセージ (`InboundMessage`) のキューイング
- 送信メッセージ (`OutboundMessage`) のキューイング
- コンテキスト付きのブロッキング受信
- チャネル名ごとのハンドラ登録・参照
- 多重 Close を避ける安全な終了処理

## 主要な型・関数・メソッド
### `type MessageBus struct`
- `inbound chan InboundMessage`
  - 外部チャネルから内部処理へ渡す受信キュー
- `outbound chan OutboundMessage`
  - 内部処理から外部チャネルへ渡す送信キュー
- `handlers map[string]MessageHandler`
  - チャネル名とハンドラの対応表
- `closed bool`
  - Close 済み判定
- `mu sync.RWMutex`
  - `closed` と `handlers` を保護するロック

### `NewMessageBus() *MessageBus`
- `inbound` / `outbound` をバッファサイズ 100 で生成する。
- `handlers` を空 map で初期化する。

### `PublishInbound(msg InboundMessage)`
- 読み取りロック取得後、`closed` を確認する。
- 未 Close の場合のみ `mb.inbound <- msg` を実行する。

### `ConsumeInbound(ctx context.Context) (InboundMessage, bool)`
- `inbound` から 1 件受信するまで待機する。
- `ctx.Done()` が先に閉じた場合は `false` を返す。

### `PublishOutbound(msg OutboundMessage)`
- `PublishInbound` と同様に、Close 済みでなければ `outbound` に送る。

### `SubscribeOutbound(ctx context.Context) (OutboundMessage, bool)`
- `outbound` から 1 件受信するまで待機する。
- `ctx.Done()` が先に閉じた場合は `false` を返す。

### `RegisterHandler(channel string, handler MessageHandler)`
- 指定チャネル名に対するハンドラを `handlers` に格納する。
- 既存キーがあれば上書きする。

### `GetHandler(channel string) (MessageHandler, bool)`
- 指定チャネルのハンドラを参照する。

### `Close()`
- 排他ロックを取り、多重 Close を防ぐ。
- `closed=true` にした上で `inbound` と `outbound` を close する。

## 詳細動作
1. 初期化時に双方向キューとハンドラ表を作る。
2. 各チャネル実装は `PublishInbound` で受信イベントを内部へ流す。
3. 内部処理は `ConsumeInbound` で受信イベントを取り出す。
4. 内部処理は応答を `PublishOutbound` に流す。
5. `pkg/channels/manager.go` の dispatcher が `SubscribeOutbound` で送信イベントを購読し、対象チャネルへ配送する。
6. `Close()` 呼び出し後は publish 系メソッドは何も送らず復帰する。

`handlers` は本ファイル内では自動実行されず、「登録・取得だけを提供するレジストリ」として実装されている。

## 入出力・副作用・永続化
### 入力
- `InboundMessage`
- `OutboundMessage`
- `context.Context`
- チャネル名と `MessageHandler`

### 出力
- `ConsumeInbound` / `SubscribeOutbound` はメッセージ本体と成功可否を返す。
- それ以外は戻り値なし。

### 副作用
- Go channel への送受信
- `handlers` map の更新
- `Close()` による channel close
- ロック取得/解放

### 永続化
- なし。完全にメモリ内で完結する。

## 依存関係
- `context`
- `sync`
- 同一パッケージ内の `InboundMessage` / `OutboundMessage` / `MessageHandler`

## エラーハンドリング・制約
- 明示的な `error` 戻り値は持たない。
- `ctx.Done()` による中断は `bool=false` で表現する。
- `PublishInbound` / `PublishOutbound` はクローズ後に silently no-op となる。
- 実装上、送信時はロックを保持したまま channel 送信するため、受信側が詰まると publish 側もブロックし得る。
- バッファ容量は 100 固定であり、溢れた場合は空きが出るまで待機する。

