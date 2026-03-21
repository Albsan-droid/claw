# response_waiter.go 詳細設計

## 対象ソース
- `pkg/tools/response_waiter.go`

## 概要
Android ツール要求と Android クライアント応答を `request_id` 単位で対応付ける待機機構を提供する。`AndroidTool.sendAndWait` から登録され、WebSocket 側受信処理から `Deliver` が呼ばれる前提で動作する。

## 責務
- `request_id` ごとの待機チャネルを管理する。
- 応答到着時に対応する待機チャネルへ 1 回だけ内容を配送する。
- タイムアウトやキャンセル時の待機情報削除を行う。

## 主要な型・関数・メソッド
### 変数
- `DeviceResponseWaiter`
  - パッケージ共通の `ResponseWaiter` シングルトン。

### 型
- `ResponseWaiter`
  - `pending map[string]chan string`
  - `mu sync.Mutex`

### 関数・メソッド
- `NewResponseWaiter()`
  - 空の `pending` マップを持つ待機機構を生成する。
- `(w *ResponseWaiter) Register(id)`
  - バッファ 1 の文字列チャネルを生成し、`pending[id]` に保存する。
- `(w *ResponseWaiter) Deliver(id, content)`
  - 対応チャネルがあれば `pending` から削除し、内容を送る。
- `(w *ResponseWaiter) Cleanup(id)`
  - 対応チャネルを `pending` から削除する。

## 詳細動作
### Register
- 排他ロックを取得する。
- `make(chan string, 1)` でバッファ付きチャネルを作る。
- `pending[id] = ch` として登録する。
- 呼び出し側へチャネルを返す。

### Deliver
- ロック下で `pending[id]` を探す。
- 見つかった場合は即座に `delete(w.pending, id)` を行う。
- ロック解除後に `ch <- content` で配送する。
- 未登録 ID の応答は黙って破棄する。

### Cleanup
- ロック下で `pending` から削除する。
- チャネル close は行わない。

## 入出力・副作用・永続化
### 入力
- `request_id string`
- 応答本文 `content string`

### 出力
- `Register` は待機用 `chan string`
- `Deliver`, `Cleanup` は戻り値なし

### 副作用
- メモリ上の `pending` マップを書き換える。
- `Deliver` は待機チャネルへメッセージを 1 件送信する。

### 永続化
- なし。

## 依存関係
- `sync.Mutex`
  - `pending` マップの排他制御に使用する。

## エラーハンドリング・制約
- エラー戻り値は持たない。
- 同じ `id` を再登録すると既存チャネル参照は上書きされる。
- `Cleanup` は存在しない `id` に対しても何もしない。
- `Deliver` は送信先チャネルの受信有無を確認しないが、バッファ 1 のため 1 回の配送ではブロックしにくい設計になっている。
