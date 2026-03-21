# pkg/gateway/handlers.go 詳細設計

## 対象ソース
- `pkg/gateway/handlers.go`

## 概要
`handlers.go` は Gateway の Config API 本体を実装する。設定スキーマ取得、現在設定取得、設定更新の3エンドポイントを担当し、必要に応じてプロセス再起動をトリガーする。

## 責務
- `GET /api/config/schema` の応答生成
- `GET /api/config` による設定ダンプ
- `PUT /api/config` による部分更新・保存・メモリ反映
- JSON レスポンス統一出力

## 主要な型・関数・メソッド
- `func (s *Server) handleGetSchema(w http.ResponseWriter, r *http.Request)`
- `func (s *Server) handleGetConfig(w http.ResponseWriter, r *http.Request)`
- `func (s *Server) handlePutConfig(w http.ResponseWriter, r *http.Request)`
- `func writeJSON(w http.ResponseWriter, code int, v interface{})`

## 詳細動作
### 1. `handleGetSchema()`
- `Accept-Language` ヘッダを `i18n.NormalizeLocale()` で正規化する。
- `config.DefaultConfig()` を雛形として `BuildSchema(defaultCfg, locale)` を実行する。
- 現在設定値ではなく「編集 UI 用の既定スキーマ」を返す実装である。

### 2. `handleGetConfig()`
- `s.cfg.RLock()` 下で `json.Marshal(s.cfg)` を実行し、共有設定を一旦 JSON 化する。
- 直後に `map[string]interface{}` へ `json.Unmarshal` し直して `raw` を作る。
- `Config.mu` のような非公開フィールドは JSON 化されないため、API 応答にも出ない。
- 成功時は `200 OK` で `raw` を返す。

### 3. `handlePutConfig()`
- 現在設定 `s.cfg` を read lock 下で JSON 文字列化し、`currentData` として退避する。
- リクエストボディは `map[string]interface{}` としてデコードする。ここでは部分更新を受け付ける。
- `incoming` を再度 `json.Marshal` して `mergedData` を作る。
- `var newCfg config.Config` を用意し、以下の 2 段階で deep copy + partial overlay を行う。
  1. `json.Unmarshal(currentData, &newCfg)`
  2. `json.Unmarshal(mergedData, &newCfg)`
- 保存時は write lock を取得し、`config.SaveConfigLocked(s.configPath, &newCfg)` を先に行う。
- 保存成功時のみ `s.cfg.CopyFrom(&newCfg)` でメモリ上の共有設定を差し替える。
- 応答は `{"status":"ok","restart":true}`。
- `s.onRestart != nil` の場合、レスポンス送信後に goroutine で `100ms` 待ってから `s.onRestart()` を呼ぶ。

### 4. `writeJSON()`
- `Content-Type: application/json` を設定し、指定ステータスコードで `json.NewEncoder(w).Encode(v)` を実行する。
- エンコード失敗時は `logger.ErrorCF("gateway", ...)` に記録するが、追加の HTTP リカバリはしない。

## 入出力・副作用・永続化
- 入力
  - HTTP `Accept-Language` ヘッダ
  - 設定更新 JSON
  - 共有設定 `s.cfg`
- 出力
  - JSON スキーマ
  - JSON 設定ダンプ
  - 更新結果 JSON
- 永続化
  - `PUT /api/config` は `s.configPath` へ保存する
- 副作用
  - `s.cfg` のメモリ内容更新
  - `s.onRestart()` による再起動通知
  - `logger` へのエラーログ出力

## 依存関係
- 設定: `pkg/config`
- i18n: `pkg/i18n`
- スキーマ生成: `pkg/gateway/schema.go` の `BuildSchema()`
- ログ: `pkg/logger`
- `Server` 型: `pkg/gateway/server.go`
- 標準ライブラリ: `encoding/json`, `net/http`, `time`

## エラーハンドリング・制約
- 不正 JSON は `400 Bad Request`。
- 現在設定の marshal/unmarshal 失敗、保存失敗は `500 Internal Server Error`。
- 部分更新は JSON ベースの overlay であり、ネスト構造の map マージ戦略は `setup.go` と異なり「リクエストで与えたオブジェクト単位で上書き」となる。
- `writeJSON()` はヘッダ送信後のエンコード失敗を回復できない。
