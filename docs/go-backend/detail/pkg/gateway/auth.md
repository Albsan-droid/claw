# pkg/gateway/auth.go 詳細設計

## 対象ソース
- `pkg/gateway/auth.go`

## 概要
`auth.go` は Gateway Config API 向けの Bearer 認証ミドルウェアを提供する。Gateway API キーが未設定なら認証を省略し、設定済みなら `Authorization: Bearer <token>` を定数時間比較で検証する。

## 責務
- `Server` ハンドラへの認証ラップ
- エラー時の JSON 形式レスポンス生成
- API キー比較時のタイミング攻撃緩和

## 主要な型・関数・メソッド
- `func (s *Server) authMiddleware(next http.HandlerFunc) http.HandlerFunc`
- `func writeJSONError(w http.ResponseWriter, code int, message string)`

## 詳細動作
### `authMiddleware()`
- `s.cfg.Gateway.APIKey` を参照する。
- API キーが空文字の場合は認証をスキップし、そのまま `next(w, r)` を呼ぶ。
- API キーが設定されている場合:
  1. `Authorization` ヘッダ未設定なら `401 Unauthorized` と `{"error":"missing Authorization header"}` を返す。
  2. ヘッダが `Bearer ` で始まらなければ `401 Unauthorized` と `invalid Authorization format` を返す。
  3. プレフィックス除去後のトークンを `crypto/subtle.ConstantTimeCompare` で `apiKey` と比較する。
  4. 不一致なら `403 Forbidden` と `invalid token` を返す。
  5. 一致時のみ `next(w, r)` を実行する。

### `writeJSONError()`
- `writeJSON()`（`pkg/gateway/handlers.go` 定義）を利用し、常に `map[string]string{"error": message}` を返す。

## 入出力・副作用・永続化
- 入力
  - `Server.cfg.Gateway.APIKey`
  - HTTP `Authorization` ヘッダ
- 出力
  - 認証成功時は後続ハンドラのレスポンス
  - 認証失敗時は JSON エラーレスポンス
- 永続化
  - なし
- 副作用
  - なし（`cfg` の読み取りのみ）

## 依存関係
- 標準ライブラリ: `crypto/subtle`, `net/http`, `strings`
- 同一パッケージ: `writeJSON()`
- `Server` 型定義: `pkg/gateway/server.go`

## エラーハンドリング・制約
- API キーが空の場合は Gateway 全体が無認証になる。
- トークン比較は定数時間比較だが、トークン長さが異なる場合の前処理は行っていない（`ConstantTimeCompare` が 0 を返す）。
- レスポンス本文は機械可読な JSON だが、エラーメッセージ自体は英語固定。
