# pkg/tools/shell.go 詳細設計

## 対象ソース
- `pkg/tools/shell.go`

## 概要
シェルコマンドを実行し、その標準出力・標準エラーを返すツールである。危険コマンドやワークスペース外パスを遮断するガードを持ち、CLI 的な問い合わせや簡易タスク実行を安全側に寄せている。

## 責務
- シェルコマンドの引数を受け取り実行する。
- 実行前に危険パターンとワークスペース逸脱を検出する。
- 実行タイムアウトを管理する。
- 出力を長さ制限付きで返す。

## 主要な型・関数・メソッド
### `type ExecTool struct`
- `workingDir`, `timeout`, `denyPatterns`, `allowPatterns`, `restrictToWorkspace`
- `NewExecTool(workingDir string, restrict bool) *ExecTool`
- `Execute(ctx, args) *ToolResult`
- `guardCommand(command, cwd string) string`
- `SetTimeout(timeout time.Duration)`
- `SetRestrictToWorkspace(restrict bool)`
- `SetAllowPatterns(patterns []string) error`

## 詳細動作
- `NewExecTool` は危険コマンド用 deny 正規表現を初期化する。対象には `rm -rf`, `del /f`, `rmdir /s`, `format`, `mkfs`, `dd if=`, `/dev/sdX` への書き込み、`shutdown`, `reboot`, フォークボムが含まれる。
- `Execute` は `command` を必須取得し、`working_dir` があれば既定値を上書きする。未設定なら `os.Getwd()` を試みる。
- `guardCommand` は denylist、任意 allowlist、`..` を含むパストラバーサル、絶対パスが `cwd` 外を指すケースをチェックする。
- 実行は Windows なら PowerShell、その他は `sh -c` を使う。
- 実行時間は `context.WithTimeout(..., 60s)` が既定で、`SetTimeout` で変更可能。
- 標準出力と標準エラーをまとめ、エラー時は終了コード相当の情報も追記する。
- 出力は 10000 文字で切り詰められる。

## 入出力・副作用・永続化
- 入力: `command`, 任意 `working_dir`, 実行コンテキスト。
- 出力: 実行出力文字列またはエラー結果。
- 副作用: OS 上でのプロセス起動、外部コマンド実行。
- 永続化: コマンド内容に依存。本ツール自体は永続層を持たない。

## 依存関係
- 標準ライブラリ: `bytes`, `context`, `fmt`, `os`, `os/exec`, `path/filepath`, `regexp`, `runtime`, `strings`, `time`
- 同一パッケージ: `ToolResult`, `ErrorResult`

## エラーハンドリング・制約
- ガードに抵触した場合は実行せず、その理由文字列を `ErrorResult` で返す。
- タイムアウト時は `Command timed out after ...` をユーザー/LLM 両方へ返す。
- `allowPatterns` を設定すると allowlist 方式へ切り替わり、合致しないコマンドは拒否される。
- 絶対パス検査は正規表現ベースであり、シェル構文のすべてを厳密解析するわけではない。
