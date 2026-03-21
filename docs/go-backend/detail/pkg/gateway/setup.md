# pkg/gateway/setup.go 詳細設計

## 対象ソース
- `pkg/gateway/setup.go`

## 概要
`setup.go` は `config.json` 未作成環境向けの Setup API を実装する。初期セットアップ (`/api/setup/init`) と、追加設定のマージ完了 (`/api/setup/complete`) を担う。

## 責務
- 設定ファイル未作成時の初期 `config.json` 生成
- Setup Wizard から送られた設定差分の既存設定へのマージ
- setup 完了後の再起動通知

## 主要な型・関数・メソッド
- `type gatewaySetupRequest struct`
- `type setupInitRequest struct`
- `func (s *Server) handleSetupInit(w http.ResponseWriter, r *http.Request)`
- `func (s *Server) handleSetupComplete(w http.ResponseWriter, r *http.Request)`

## 詳細動作
### 1. リクエスト構造
- `gatewaySetupRequest`
  - `Port int` (`json:"port"`)
  - `APIKey string` (`json:"api_key"`)
- `setupInitRequest`
  - `Gateway gatewaySetupRequest` (`json:"gateway"`)

### 2. `handleSetupInit()`
- 想定エンドポイント: `POST /api/setup/init`
- 認証不要。
- `os.Stat(s.configPath)` が成功した場合、既に設定があると判断して `409 Conflict` を返す。
- リクエスト JSON を `setupInitRequest` にデコードし、失敗時は `400 Bad Request`。
- `cfg := config.DefaultConfig()` を作成し、`req.Gateway.Port > 0` の場合のみ `cfg.Gateway.Port` を上書きする。
- `cfg.Gateway.APIKey = req.Gateway.APIKey` は空文字も含めてそのまま反映する。
- `config.SaveConfig(s.configPath, cfg)` に成功すれば `{"status":"ok"}` を返す。
- 失敗時は `logger.ErrorCF("gateway", "Failed to save initial config", ...)` を出し、`500 Internal Server Error` を返す。

### 3. `handleSetupComplete()`
- 想定エンドポイント: `PUT /api/setup/complete`
- `authMiddleware` 付きで呼ばれるが、実際に `Authorization: Bearer <token>` が必要なのは `cfg.Gateway.APIKey` が空でない場合だけである。`handleSetupInit()` では空文字の API キーも保存できるため、セットアップ状態によっては実質無認証になる。
- 現在設定は `s.cfg` ではなく `os.ReadFile(s.configPath)` でディスクから直接読む。理由は setup mode 中の `s.cfg` が `DefaultConfig()` のまま残っている可能性があるため。
- ボディは `map[string]interface{}` で受け、`agents_extra` キーに特別対応する。
  - `incoming["agents_extra"]` があれば `incoming["agents"]` へ deep merge する。
  - 1段深い map 同士 (`agents[k]` と `extra[k]`) の場合はネスト key ごとに上書きする。
  - マージ後に `agents_extra` は削除する。
- その後 `incoming` を JSON 化し、`newCfg` に対して
  1. 現在設定 JSON を unmarshal
  2. `incoming` JSON を unmarshal
  することで部分更新を適用する。
- 保存は `s.cfg.Lock()` 下で `config.SaveConfigLocked(s.configPath, &newCfg)` を先に行い、成功時のみ `s.cfg.CopyFrom(&newCfg)` する。
- 応答成功後、`s.onRestart != nil` なら別 goroutine で `100ms` 後に `s.onRestart()` を呼ぶ。

## 入出力・副作用・永続化
- 入力
  - Setup Wizard の JSON リクエスト
  - `s.configPath` 上の既存設定ファイル
- 出力
  - `{"status":"ok"}` または JSON エラー
- 永続化
  - `s.configPath` の `config.json`
- 副作用
  - `s.cfg` のメモリ内容更新
  - `logger` へのエラーログ出力
  - 再起動コールバック呼び出し

## 依存関係
- 設定: `pkg/config`
- ログ: `pkg/logger`
- 同一パッケージ: `writeJSON()`, `writeJSONError()`, `Server`
- 標準ライブラリ: `encoding/json`, `net/http`, `os`, `time`

## エラーハンドリング・制約
- `handleSetupInit()` は設定ファイルがあると上書きしない。
- `agents_extra` のマージは map ベースであり、配列やさらに深い階層への汎用 deep merge ではない。
- 設定保存失敗時はメモリ更新を行わない。
- 成功後の再起動は非同期で、即時には行われない（100ms 遅延）。
