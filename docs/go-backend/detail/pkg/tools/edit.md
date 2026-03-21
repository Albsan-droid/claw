# pkg/tools/edit.go 詳細設計

## 対象ソース
- `pkg/tools/edit.go`

## 概要
既存ファイルの部分置換と追記を提供する編集系ツール群である。置換は「対象文字列がちょうど 1 回だけ出現する」ことを要求し、曖昧な編集を避ける。

## 責務
- 既存ファイル中の `old_text` を `new_text` へ 1 回だけ置換する。
- ファイル末尾への追記を提供する。
- いずれの操作でも `filesystem.go` の `validatePath` を使ってアクセス範囲を制限する。

## 主要な型・関数・メソッド
### `type EditFileTool`
- フィールド: `allowedDir`, `restrict`
- `NewEditFileTool(allowedDir string, restrict bool) *EditFileTool`
- `Execute(ctx, args) *ToolResult`

### `type AppendFileTool`
- フィールド: `workspace`, `restrict`
- `NewAppendFileTool(workspace string, restrict bool) *AppendFileTool`
- `Execute(ctx, args) *ToolResult`

## 詳細動作
### `EditFileTool.Execute`
1. `path`, `old_text`, `new_text` を必須取得する。
2. `validatePath` で対象パスを解決する。
3. `os.Stat` で存在確認し、なければ `file not found` を返す。
4. ファイル内容を読み込み、`strings.Contains` で `old_text` の存在を確認する。
5. `strings.Count` が 2 以上なら「曖昧な編集」とみなし、より広い文脈指定を促す。
6. `strings.Replace(..., 1)` で 1 回だけ置換し、`os.WriteFile(..., 0644)` で保存する。
7. 成功時は `SilentResult("File edited: ...")` を返す。

### `AppendFileTool.Execute`
1. `path`, `content` を必須取得する。
2. `validatePath` で対象パスを解決する。
3. `os.OpenFile(path, O_APPEND|O_CREATE|O_WRONLY, 0644)` でファイルを開く。
4. `WriteString(content)` で末尾へ追記する。
5. 成功時は `SilentResult("Appended to ...")` を返す。

## 入出力・副作用・永続化
- 入力: `path`, `old_text`, `new_text`, `content`, ワークスペース/許可ディレクトリ設定。
- 出力: 無言成功結果またはエラー結果。
- 副作用: ファイル読み書き、必要に応じた新規ファイル作成（追記ツール）。
- 永続化: ファイル内容の更新。

## 依存関係
- 標準ライブラリ: `context`, `fmt`, `os`, `strings`
- 同一パッケージ: `validatePath`, `SilentResult`, `ErrorResult`

## エラーハンドリング・制約
- `EditFileTool` は `old_text` が 0 回または 2 回以上出現する場合に失敗する。
- `AppendFileTool` は親ディレクトリを自動作成しないため、存在しないディレクトリへの追記は OS エラーになる。
- いずれも `validatePath` によりワークスペース外や危険なシンボリックリンクを拒否する。
