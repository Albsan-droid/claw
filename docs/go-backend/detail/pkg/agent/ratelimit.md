# pkg/agent/ratelimit.go

## 対象ソース
- `pkg/agent/ratelimit.go`

## 概要
`rateLimiter` は、1 分間あたりのリクエスト数とツールコール数をメモリ内で制限する単純なスライディングウィンドウ実装である。

## 責務
- ツールコール回数の抑制
- リクエスト回数の抑制
- 古いタイムスタンプの切り落とし
- goroutine 競合の防止

## 主要な型・関数・メソッド
### 型
- `rateLimiter`
  - `maxToolCallsPerMinute`
  - `maxRequestsPerMinute`
  - `mu sync.Mutex`
  - `toolCallTimes []time.Time`
  - `requestTimes []time.Time`

### 関数・メソッド
- `newRateLimiter(maxToolCalls, maxRequests int) *rateLimiter`
- `checkToolCall() error`
- `checkRequest() error`
- `pruneOld(times []time.Time, cutoff time.Time) []time.Time`

## 詳細動作
- `checkToolCall` / `checkRequest` はほぼ同じロジックを別配列に対して実行する。
- 制限値が `<= 0` の場合は無制限扱いで即 `nil` を返す。
- それ以外では `time.Now()` から 1 分前の `cutoff` を計算し、`pruneOld` で期限切れエントリを除去する。
- 除去後の件数が上限以上なら `fmt.Errorf("... limit exceeded (%d/min)")` を返す。
- 許可される場合は現在時刻を末尾へ追加する。
- `pruneOld` はスライス先頭から `cutoff` より前の要素数を数え、その位置から後ろを返す。

## 入出力・副作用・永続化
### 入力
- 1 分あたり上限値
- 現在時刻（内部で `time.Now()` を使用）

### 出力
- 許可時 `nil`
- 超過時 `error`

### 副作用
- 内部スライスの更新
- `sync.Mutex` による排他制御

### 永続化
- なし。プロセス再起動で全カウンタはリセットされる。

## 依存関係
- 標準ライブラリ: `fmt`, `sync`, `time`

## エラーハンドリング・制約
- スライディングウィンドウは配列走査ベースで、件数が増えるほど `O(n)` になる。
- タイムスタンプは append 順を前提にしており、途中挿入やソートはしない。
- 永続化されないため、分散環境や複数プロセス間では共有されない。
