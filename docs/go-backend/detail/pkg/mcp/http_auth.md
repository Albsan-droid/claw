# pkg/mcp/http_auth.go 詳細設計

## 対象ソース
- `pkg/mcp/http_auth.go`

## 概要
MCP の HTTP トランスポートへ任意ヘッダーを注入する `http.RoundTripper` ラッパーである。認証トークンやカスタムヘッダーを、元リクエストを破壊せずに毎回付与する目的で使われる。

## 責務
- HTTP リクエストを複製し、追加ヘッダーを書き込む。
- 実際の送信は下位 `RoundTripper` に委譲する。

## 主要な型・関数・メソッド
### `type headerTransport struct`
- `headers map[string]string`
- `base http.RoundTripper`

### `func (t *headerTransport) RoundTrip(req *http.Request) (*http.Response, error)`
- リクエストを `req.Clone(req.Context())` で複製してからヘッダーを設定する。

## 詳細動作
- `RoundTrip` は元の `req` を直接変更せず、clone 側へ `headers` の内容を `Header.Set` で上書きする。
- その後 `t.base.RoundTrip(req)` を呼び、レスポンスやエラーはそのまま上位へ返す。
- `manager.go` では `cfg.Headers` が 1 件以上ある HTTP MCP サーバーに対してこのラッパーを使う。

## 入出力・副作用・永続化
- 入力: HTTP リクエスト、注入ヘッダー集合、下位 `RoundTripper`。
- 出力: HTTP レスポンスまたはエラー。
- 副作用: 送信リクエストヘッダーの変更（clone したリクエストに対してのみ）。
- 永続化: なし。

## 依存関係
- 標準ライブラリ: `net/http`
- 利用側: `pkg/mcp/manager.go`

## エラーハンドリング・制約
- `base` が `nil` の場合の防御コードは無く、そのまま呼ぶと panic 相当の問題になり得る。
- `Header.Set` により同名ヘッダーは上書きされる。
