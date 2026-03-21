# pkg/tools/filesystem.go 詳細設計

## 対象ソース
- `pkg/tools/filesystem.go`

## 概要
ワークスペース配下のファイル・ディレクトリ操作を安全に実行するための共通ファイルシステムツール群である。パス検証・シンボリックリンク解決・相対パス正規化を行うヘルパーと、読み取り・書き込み・ディレクトリ列挙ツールを含む。

## 責務
- ワークスペース外アクセスを防ぐ `validatePath` 系ヘルパーを提供する。
- ファイル読み取り (`ReadFileTool`) を提供する。
- ファイル書き込み (`WriteFileTool`) を提供する。
- ディレクトリ一覧取得 (`ListDirTool`) を提供する。
- `copy_file.go` と `edit.go` から再利用されるパス安全性判定を担う。

## 主要な型・関数・メソッド
### パス検証ヘルパー
- `validatePath(path, workspace string, restrict bool) (string, error)`
- `resolveExistingAncestor(path string) (string, error)`
- `isWithinWorkspace(candidate, workspace string) bool`

### `type ReadFileTool`
- `NewReadFileTool(workspace string, restrict bool) *ReadFileTool`
- `Execute(ctx, args)` はファイル内容を `NewToolResult` で返す。

### `type WriteFileTool`
- `NewWriteFileTool(workspace string, restrict bool) *WriteFileTool`
- `Execute(ctx, args)` は必要に応じて親ディレクトリを作成して上書き保存する。

### `type ListDirTool`
- `NewListDirTool(workspace string, restrict bool) *ListDirTool`
- `Execute(ctx, args)` は `DIR:` / `FILE:` プレフィックス付きの一覧文字列を返す。

## 詳細動作
- `validatePath` は `workspace` が空なら入力パスをそのまま返す。
- 相対パスは `workspace` 基準で絶対パス化する。絶対パス入力は `filepath.Clean` で正規化する。
- `restrict=true` の場合、以下を検査する。
  - パスがワークスペース配下にあるか
  - ワークスペース自身の実体パス (`EvalSymlinks`) が解決可能ならそれを基準にする
  - 対象が存在する場合は実体パスがワークスペース外へ出ないか
  - 対象が未作成の場合は既存祖先ディレクトリの実体パスで同様に検査する
- `WriteFileTool` は `os.MkdirAll(dir, 0755)` の後に `os.WriteFile(..., 0644)` で保存する。
- `ListDirTool` の `path` は未指定時に `.` を採用する。

## 入出力・副作用・永続化
- 入力: `path`, `content` などのツール引数、ワークスペースパス、restrict フラグ。
- 出力: ファイル内容、一覧文字列、または無言成功結果。
- 副作用: ファイル読み書き、ディレクトリ作成、シンボリックリンク解決。
- 永続化: ファイルシステムに対する書き込みのみ。

## 依存関係
- 標準ライブラリ: `context`, `fmt`, `os`, `path/filepath`, `strings`
- 同一パッケージ: `ToolResult`, `ErrorResult`, `NewToolResult`, `SilentResult`
- 利用側: `copy_file.go`, `edit.go`

## エラーハンドリング・制約
- ワークスペース外パスは `access denied` エラーを返す。
- シンボリックリンクがワークスペース外へ解決される場合も拒否する。
- 読み書き・列挙失敗時は OS エラーをラップしたメッセージを返す。
- `ListDirTool` は一覧をソートしないため、返却順序は OS 依存である。
