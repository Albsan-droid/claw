# pkg/tools/copy_file.go 詳細設計

## 対象ソース
- `pkg/tools/copy_file.go`

## 概要
ワークスペース内ファイル、またはメディアディレクトリ上のファイルをワークスペース内へコピーするツールである。スクリーンショットや撮影画像を作業ディレクトリへ取り込む用途を想定し、コピー元とコピー先で許可範囲を分けている。

## 責務
- `source` と `destination` の引数を検証する。
- コピー元をワークスペースまたは `mediaDir` に限定する。
- コピー先を常にワークスペース内に限定する。
- 必要に応じてコピー先の親ディレクトリを作成する。

## 主要な型・関数・メソッド
### `type CopyFileTool`
- フィールド: `workspace`, `mediaDir`, `restrict`
- `NewCopyFileTool(workspace, mediaDir string, restrict bool) *CopyFileTool`
- `Execute(ctx, args) *ToolResult`
- `validateSource(source string) (string, error)`

## 詳細動作
- `Execute` は `source` と `destination` を文字列として必須取得する。
- コピー元検証は `validateSource` が担当する。
  1. まず `validatePath(source, workspace, restrict)` を試す。
  2. 失敗し、かつ `restrict=true` で `mediaDir` が設定されている場合のみ、`mediaDir` 基準の相対/絶対パスとして再解決する。
  3. `isWithinWorkspace(absSource, absMediaDir)` が true のときだけ許可する。
- コピー先は `validatePath(destination, workspace, true)` で常にワークスペース内限定とする。
- 実際のコピーは `os.ReadFile` → `os.MkdirAll(filepath.Dir(dstPath), 0755)` → `os.WriteFile(dstPath, data, 0644)` の順に行う。
- 成功時は `SilentResult("File copied: ...")` を返すため、ユーザーへの直接通知は行わない。

## 入出力・副作用・永続化
- 入力: `source`, `destination`, ワークスペースパス、メディアディレクトリ、restrict フラグ。
- 出力: 無言成功結果またはエラー結果。
- 副作用: ソースファイル読み取り、宛先ディレクトリ作成、宛先ファイル書き込み。
- 永続化: 宛先ファイルの作成・更新。

## 依存関係
- 標準ライブラリ: `context`, `fmt`, `os`, `path/filepath`
- 同一パッケージ: `validatePath`, `isWithinWorkspace`, `SilentResult`, `ErrorResult`

## エラーハンドリング・制約
- `source` / `destination` 未指定時は即エラー。
- `restrict=true` の場合、コピー元はワークスペース外でも `mediaDir` 配下なら許容されるが、それ以外は拒否される。
- `mediaDir` の絶対化失敗時は汎用的な `access denied` を返す。
- 宛先は常にワークスペース内固定であり、`mediaDir` への書き込みは不可。
