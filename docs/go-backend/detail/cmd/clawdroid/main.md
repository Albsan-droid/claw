# cmd/clawdroid/main.go 詳細設計

## 対象ソース
- `cmd/clawdroid/main.go`

## 概要
`main.go` は Go バックエンドのエントリポイントであり、CLI サブコマンドの振り分け、設定ロード、Gateway 起動、Agent 実行、Cron/Skills 操作、初期セットアップを統括する。`clawdroid` バイナリの実行形態はこの 1 ファイルで分岐される。

## 責務
- `main()` によるサブコマンドディスパッチ（`onboard` / `agent` / `gateway` / `status` / `cron` / `skills` / `version`）
- 起動時環境の調整（`TZ` によるローカルタイム設定、DNS/CA 設定）
- 組み込み `workspace/` テンプレートの配布
- `pkg/agent`・`pkg/gateway`・`pkg/channels`・`pkg/cron`・`pkg/heartbeat` の起動順制御
- Gateway 再起動時の `syscall.Exec` 実行
- CLI からの Cron / Skills 運用操作

## 主要な型・関数・メソッド
- グローバル変数
  - `var embeddedFiles embed.FS` — `//go:embed workspace` で埋め込まれたテンプレート群
  - `var version, gitCommit, buildTime, goVersion string` — ビルド時埋め込み情報
  - `const logo = "🦞"`
- 初期化
  - `func init()` (1つ目) — `TZ` 環境変数があれば `time.LoadLocation` で `time.Local` を更新
  - `func init()` (2つ目) — 条件分岐なしで `net.DefaultResolver.Dial` を `8.8.8.8:53` に固定し、`SSL_CERT_DIR=/system/etc/security/cacerts` を必要時のみ設定する。コードコメント上の意図は Android の pure-Go 実行向け補正だが、CGO 有効ビルドでは通常 cgo resolver が使われる
- バージョン表示
  - `formatVersion()`
  - `formatBuildInfo()`
  - `printVersion()`
- ファイル配布
  - `copyDirectory(src, dst string) error`
  - `copyEmbeddedToTarget(targetDir string) error`
  - `createWorkspaceTemplates(workspace string)`
- コマンド入口
  - `main()`
  - `printHelp()`
  - `onboard()`
  - `agentCmd()`
  - `gatewayCmd()`
  - `gatewaySetupMode(cfg *config.Config, configPath string)`
  - `statusCmd()`
  - `cronCmd()` / `cronHelp()` / `cronListCmd()` / `cronAddCmd()` / `cronRemoveCmd()` / `cronEnableCmd()`
  - `skillsHelp()` / `skillsListCmd()` / `skillsRemoveCmd()` / `skillsInstallBuiltinCmd()` / `skillsListBuiltinCmd()` / `skillsShowCmd()`
- 対話補助
  - `interactiveMode(agentLoop *agent.AgentLoop, sessionKey string)`
  - `simpleInteractiveMode(agentLoop *agent.AgentLoop, sessionKey string)`
- 補助
  - `execRestart()`
  - `getConfigPath()`
  - `setupCronTool(...) *cron.CronService`
  - `loadConfig() (*config.Config, error)`

## 詳細動作
### 1. 起動前初期化
- 1つ目の `init()` は `TZ` が設定済みなら `time.LoadLocation` 成功時のみ `time.Local` を更新する。失敗時は無視する。
- 2つ目の `init()` は条件分岐なしで `net.DefaultResolver.Dial` を差し替え、`udp/8.8.8.8:53` を直接参照する。コードコメントでは Android APK など `CGO_ENABLED=0` の pure-Go 実行時を想定しているが、CGO 有効ビルドでは通常 cgo resolver が使われるため、このフックが実際に呼ばれないことがある。
  - TLS は `SSL_CERT_FILE` と `SSL_CERT_DIR` の両方が未設定で、かつ `/system/etc/security/cacerts` が存在する場合のみ `SSL_CERT_DIR` を設定する。

### 2. `main()` のコマンド分岐
- `os.Args[1]` をサブコマンドとして解釈する。
- 引数不足時は `printHelp()` 後に `os.Exit(1)`。
- `skills` は `loadConfig()` 後に `skills.NewSkillsLoader(dataDir, globalSkillsDir, builtinSkillsDir)` を生成し、さらに `list/remove/install-builtin/list-builtin/show` へ分岐する。
- `version/--version/-v` は `printVersion()` を実行する。
- 未知のサブコマンドはヘルプ表示後に終了する。

### 3. 初期セットアップ `onboard()`
- 設定ファイルパスは `getConfigPath()` に固定され、実体は `~/.clawdroid/config.json`。
- 既存設定がある場合は標準入力で上書き確認を取る。
- `config.DefaultConfig()` を保存し、`cfg.WorkspacePath()` と `cfg.DataPath()` を算出する。
- `createWorkspaceTemplates(dataDir)` を呼んで埋め込みテンプレートを書き出す。引数名は `workspace` だが、呼び出し元は `dataDir` を渡している点に注意。

### 4. Agent モード `agentCmd()`
- オプション:
  - `--debug` / `-d` — `logger.SetLevel(logger.DEBUG)`
  - `-m` / `--message` — 単発メッセージ
  - `-s` / `--session` — セッションキー。既定値は `cli:default`
- `loadConfig()` → `providers.CreateProvider(cfg)` → `bus.NewMessageBus()` → `agent.NewAgentLoop(cfg, msgBus, provider)` の順に初期化する。
- `message` 指定時は `agentLoop.ProcessDirect(context.Background(), message, sessionKey)` を1回実行して応答を表示する。
- `message` 未指定時は `interactiveMode()` に入り、対話ループを継続する。

### 5. 対話モード
- `interactiveMode()` は `github.com/chzyer/readline` を使用し、履歴ファイルを `filepath.Join(os.TempDir(), ".clawdroid_history")` に保存する。
- `readline.NewEx` に失敗した場合は `simpleInteractiveMode()` へフォールバックする。
- 両モードとも `exit` / `quit` を終了トリガーとし、各入力を `agentLoop.ProcessDirect()` に渡す。

### 6. Gateway モード `gatewayCmd()`
- `--debug` / `-d` を検出するとログレベルを DEBUG に上げる。
- `configPath := getConfigPath()` と `cfg := loadConfig()` を得た後、設定ファイルが存在しなければ `gatewaySetupMode(cfg, configPath)` を実行する。
- 通常起動時は以下の順序で初期化する。
  1. `msgBus := bus.NewMessageBus()`
  2. `restartCh := make(chan struct{}, 1)`
  3. `gwServer := gateway.NewServer(cfg, configPath, onRestart)` を生成し `Start()`
  4. `channels.NewManager(cfg, msgBus, configPath)` を生成し `StartAll(ctx)`
  5. `providers.CreateProvider(cfg)` を試行
- LLM プロバイダ生成失敗時は degraded mode に入り、`msgBus.ConsumeInbound(ctx)` から受けた各メッセージへ固定警告文を `PublishOutbound` で返す。Config API と Channel は生かし続ける。
- 成功時は `agent.NewAgentLoop` を作成し、`SetChannelManager()`、`setupCronTool()`、`heartbeat.NewHeartbeatService()`、`heartbeatService.SetBus()`、`heartbeatService.SetHandler()` を順に設定する。
- `cronService.Start()` と `heartbeatService.Start()` は `go agentLoop.Run(ctx)` より前に実行されるため、スケジューラ系サービスはメインの inbound ループ開始前から稼働する。
- `heartbeatService.SetHandler()` では `agentLoop.ProcessHeartbeat()` をラップし、非エラー応答は `HEARTBEAT_OK` を含めてすべて `tools.SilentResult(...)` に変換する。さらに `ProcessHeartbeat()` 自体も `SendResponse: false` で動作するため、既定の gateway 配線では heartbeat の非エラー結果は通常チャネルへ配信されない。
- 終了契機は `os.Interrupt` / `SIGTERM` または `restartCh`。再起動時は終了処理後に `execRestart()` を呼ぶ。

### 7. Setup モード `gatewaySetupMode()`
- Config 不在時の最小構成起動。
- `gateway.NewServer()` と `channels.NewManager()` のみ起動し、`pkg/providers`・`pkg/agent`・`pkg/cron`・`pkg/heartbeat` は起動しない。
- `restartCh` 受信時は「setup complete 後の再起動」とみなし、停止後に `execRestart()` を呼ぶ。

### 8. ステータス表示 `statusCmd()`
- `loadConfig()` を行い、設定ファイル・ワークスペースの存在、モデル、API キー設定有無、`BaseURL` を表示する。
- ビルド日時は `formatBuildInfo()` の戻り値を使う。

### 9. Cron 操作
- `cronCmd()` は `cfg.DataPath()/cron/jobs.json` をストアとする。
- `cronListCmd()` は `cron.NewCronService(storePath, nil).ListJobs(true)` を使い、無効ジョブを含めて表示する。
- `cronAddCmd()` は `--name`、`--message`、`--every` または `--cron` を解析して `cron.CronSchedule` を構築し、`AddJob()` を呼ぶ。
- `cronEnableCmd()` は `EnableJob(jobID, enabled)` を呼ぶ。

### 10. Skills 操作
- `skillsListCmd()` は `loader.ListSkills()` を列挙する。
- `skillsRemoveCmd()` は `dataDir/skills/<skillName>` を `os.RemoveAll` で削除する。
- `skillsInstallBuiltinCmd()` は `./clawdroid/skills` から `dataDir/skills` へ `copyDirectory()` で複製するが、現状 `skillsToInstall := []string{}` のため実質コピー対象は空。
- `skillsListBuiltinCmd()` は `filepath.Dir(cfg.WorkspacePath())/clawdroid/skills` を走査する。
- `skillsShowCmd()` は `loader.LoadSkill(skillName)` の内容をそのまま標準出力へ流す。

## 入出力・副作用・永続化
- 入力
  - `os.Args` によるサブコマンド・フラグ解析
  - `stdin` による `onboard()` 確認入力、対話モード入力
  - 環境変数 `TZ`、`SSL_CERT_FILE`、`SSL_CERT_DIR`
- 出力
  - 標準出力/標準エラーへのステータス表示
  - `logger` を経由したログ出力
- 永続化
  - `~/.clawdroid/config.json`
  - `cfg.DataPath()/cron/jobs.json`
  - `dataDir/skills/...`
  - 埋め込み `workspace/` テンプレートの展開先ディレクトリ
  - `os.TempDir()/.clawdroid_history`（readline 履歴）
- 副作用
  - `syscall.Exec` による自己再実行
  - `signal.Notify` 登録
  - `net.DefaultResolver.Dial` と `time.Local` のグローバル更新
  - `os.Setenv("SSL_CERT_DIR", ...)`

## 依存関係
- 設定: `pkg/config`
- Agent 実行: `pkg/agent`, `pkg/providers`, `pkg/tools`
- メッセージング: `pkg/bus`, `pkg/channels`
- Gateway: `pkg/gateway`
- 定期実行: `pkg/cron`, `pkg/heartbeat`
- Skills: `pkg/skills`
- ログ: `pkg/logger`
- UI 入力: `github.com/chzyer/readline`
- 標準ライブラリ: `context`, `embed`, `net`, `os/signal`, `syscall`, `time` など

## エラーハンドリング・制約
- 多くの初期化失敗は `fmt.Printf(...); os.Exit(1)` で即時終了する。
- `TZ` 読み込み失敗や `SSL_CERT_DIR` 設定失敗は無視される。
- degraded mode では Config API と Channel を維持するが、AgentLoop / Cron / Heartbeat は起動しない。
- `execRestart()` は `os.Executable()` または `syscall.Exec()` 失敗時に終了する。
- `copyEmbeddedToTarget()` / `copyDirectory()` は途中失敗を呼び出し元へ返す。
- `skillsListBuiltinCmd()` の説明抽出は簡易実装で、`SKILL.md` の解析精度は高くない。
- `createWorkspaceTemplates()` は内部でエラーを表示するだけで呼び出し元へ返さない。
