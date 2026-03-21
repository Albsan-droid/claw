# pkg/mcp/manager.go 詳細設計

## 対象ソース
- `pkg/mcp/manager.go`

## 概要
複数の MCP サーバーを設定ベースで管理し、必要時起動、ツール一覧取得、ツール呼び出し、リソース読み込み、アイドル停止、再接続制御まで行うライフサイクル管理コンポーネントである。stdio サーバーと HTTP サーバーの両方を扱う。

## 責務
- MCP サーバー設定を保持し、名前で管理する。
- サーバーを必要時に起動・接続する。
- ツール一覧とリソース内容を取得する。
- セッション障害時に再起動可能な状態へ戻す。
- アイドルセッションを定期的にクリーンアップする。
- system prompt 用のサーバー要約 XML を生成する。

## 主要な型・関数・メソッド
### `type ServerInstance`
- `session *sdkmcp.ClientSession`
- `done chan struct{}`
- `tools []*sdkmcp.Tool`
- `lastUsed time.Time`
- `crashes []time.Time`
- `isHTTP bool`
- `mu sync.Mutex`

### `type Manager`
- `configs map[string]config.MCPServerConfig`
- `servers map[string]*ServerInstance`
- `mu sync.RWMutex`
- `stopCh chan struct{}`
- `wg sync.WaitGroup`

### 主な API
- `NewManager(configs map[string]config.MCPServerConfig) *Manager`
- `ListServers() []ServerSummary`
- `GetTools(ctx, serverName string) ([]*sdkmcp.Tool, error)`
- `CallTool(ctx, serverName, toolName string, args map[string]interface{}) (string, error)`
- `ReadResource(ctx, serverName, uri string) (string, error)`
- `BuildSummary() string`
- `Stop()`

### 内部処理
- `ensureRunning(ctx, serverName string) (*ServerInstance, error)`
- `handleSessionError(serverName string, inst *ServerInstance, err error)`
- `idleReaper()`
- `reapIdleServers()`
- `extractText(result *sdkmcp.CallToolResult) string`

## 詳細動作
### 起動・接続 (`ensureRunning`)
1. 設定存在確認と `Enabled` 判定を行う。
2. `servers` マップから `ServerInstance` を取得し、無ければ新規作成する。
3. 既存セッションがある場合は `done` を non-blocking に確認し、終了済みなら破棄・再接続、存続中ならそのまま返す。
4. 直近 60 秒以内の `crashes` を絞り込み、3 回以上なら再接続を拒否する。
5. `sdkmcp.NewClient` でクライアント生成。
6. `cfg.URL` があれば HTTP。`cfg.Headers` があれば `headerTransport` を挟んだ `http.Client` を使う。URL が無ければ `cfg.Command` + `cfg.Args` の stdio 実行となる。
7. `client.Connect(...)` で MCP ハンドシェイクを実行し、`session.Wait()` 監視 goroutine で `done` を閉じる。
8. `lastUsed` 更新、ツールキャッシュクリア、初期化ログ出力。

### 通常操作
- `GetTools` はキャッシュ済み `inst.tools` を優先し、未取得時のみ `session.ListTools` を呼ぶ。
- `CallTool` は `session.CallTool` の結果を `extractText` で文字列化し、`IsError` が立っていればエラー扱いにする。
- `ReadResource` は複数 content block を走査し、text はそのまま、blob は `[blob: mime, size bytes]` 形式へ変換して結合する。

### アイドル停止
- `idleReaper` は 30 秒ごとに `reapIdleServers` を呼ぶ。
- `IdleTimeout <= 0` の場合は 300 秒を既定値とする。
- `lastUsed` からの経過が timeout を超えたら `session.Close()` し、ツールキャッシュも破棄する。

### 要約生成
- `BuildSummary` は起動せず設定だけを見て `<mcp_servers>` XML 風文字列を作る。

## 入出力・副作用・永続化
- 入力: `config.MCPServerConfig` 群、サーバー名、ツール名、引数、リソース URI。
- 出力: サーバー一覧、SDK ツール一覧、ツール実行結果文字列、リソース本文、XML サマリ。
- 副作用: 外部プロセス起動、HTTP 接続、環境変数付与、セッション close、ログ出力、バックグラウンド goroutine 起動。
- 永続化: なし。状態はメモリ内セッションキャッシュのみ。

## 依存関係
- 標準ライブラリ: `context`, `encoding/json`, `fmt`, `net/http`, `os`, `os/exec`, `strings`, `sync`, `time`
- 他パッケージ: `pkg/config`, `pkg/logger`, `github.com/modelcontextprotocol/go-sdk/mcp`
- 同一パッケージ: `ServerSummary`, `headerTransport`

## エラーハンドリング・制約
- 未知サーバー、無効化済みサーバー、接続失敗は明示的エラー。
- `handleSessionError` はエラー文字列に `write/read/pipe/process/http/connection/EOF` を含む場合のみ transport error とみなす。
- `BuildSummary` では `configs` の map 反復順をそのまま使うため、出力順は固定ではない。
- `Stop` は `stopCh` を close する設計なので多重呼び出しは想定されていない。
