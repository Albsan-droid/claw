# pkg/gateway/server.go 詳細設計

## 対象ソース
- `pkg/gateway/server.go`

## 概要
`server.go` は Config API 用 HTTP サーバのライフサイクルを管理する。`Server` は共有設定、設定ファイルパス、再起動コールバックを保持し、ローカルホスト `127.0.0.1` 専用で API を公開する。

## 責務
- `Server` インスタンス生成
- Config API / Setup API のルーティング設定
- HTTP サーバ起動・停止
- 起動/異常終了時のログ出力

## 主要な型・関数・メソッド
- `type Server struct`
  - `cfg *config.Config`
  - `configPath string`
  - `server *http.Server`
  - `onRestart func()`
- `func NewServer(cfg *config.Config, configPath string, onRestart func()) *Server`
- `func (s *Server) Start() error`
- `func (s *Server) Stop(ctx context.Context) error`

## 詳細動作
### `NewServer()`
- 共有設定ポインタ、保存先パス、再起動フックを保持するだけの薄いコンストラクタ。

### `Start()`
- `http.NewServeMux()` を作成し、以下ルートを登録する。
  - `GET /api/config/schema` → `s.authMiddleware(s.handleGetSchema)`
  - `GET /api/config` → `s.authMiddleware(s.handleGetConfig)`
  - `PUT /api/config` → `s.authMiddleware(s.handlePutConfig)`
  - `POST /api/setup/init` → `s.handleSetupInit`
  - `PUT /api/setup/complete` → `s.authMiddleware(s.handleSetupComplete)`
- リッスン先は `fmt.Sprintf("127.0.0.1:%d", s.cfg.Gateway.Port)`。
- `s.server = &http.Server{Addr: addr, Handler: mux}` を作成し、別 goroutine で `ListenAndServe()` を実行する。
- `http.ErrServerClosed` 以外の終了は `logger.ErrorCF("gateway", ...)` に記録する。
- `Start()` 自体は非同期起動後すぐ `nil` を返す。

### `Stop(ctx)`
- `s.server == nil` なら何もせず `nil` を返す。
- サーバ存在時は `s.server.Shutdown(ctx)` を実行し、graceful shutdown を呼び出し元へ委譲する。

## 入出力・副作用・永続化
- 入力
  - `cfg.Gateway.Port`
  - 各ハンドラに届く HTTP リクエスト
- 出力
  - `127.0.0.1:<port>` の HTTP API
- 永続化
  - なし（保存処理自体は各ハンドラが担当）
- 副作用
  - バックグラウンド goroutine 起動
  - `logger` へのログ出力

## 依存関係
- 設定: `pkg/config`
- ログ: `pkg/logger`
- 同一パッケージのハンドラ: `auth.go`, `handlers.go`, `setup.go`
- 標準ライブラリ: `context`, `fmt`, `net/http`

## エラーハンドリング・制約
- `Start()` はポート bind 成功前に `nil` を返し得るため、起動直後エラーは goroutine 側ログでしか観測できない。
- バインド先は固定で `127.0.0.1`。外部インタフェースへは公開しない。
- `Stop()` のキャンセル/タイムアウトは呼び出し側 `ctx` に依存する。
