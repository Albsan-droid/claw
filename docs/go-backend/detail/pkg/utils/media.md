# pkg/utils/media.go

## 対象ソース
- `pkg/utils/media.go`

## 概要
メディア関連の汎用ユーティリティ群。ローカル画像ファイルを base64 data URL に変換する処理と、URL から一時ディレクトリへファイルをダウンロードする処理を提供する。

## 責務
- ローカル画像ファイルの data URL 化
- 危険なファイル名の簡易サニタイズ
- HTTP GET によるファイルダウンロード
- 一時メディア保存ディレクトリの管理

## 主要な型・関数・メソッド
### 定数
- `maxImageFileSize = 50 * 1024 * 1024`

### 型
- `DownloadOptions`
  - `Timeout time.Duration`
  - `ExtraHeaders map[string]string`
  - `LoggerPrefix string`

### 関数
- `EncodeFileToDataURL(path string) string`
- `SanitizeFilename(filename string) string`
- `DownloadFile(url, filename string, opts DownloadOptions) string`
- `DownloadFileSimple(url, filename string) string`

## 詳細動作
### `EncodeFileToDataURL`
- 拡張子を小文字化して MIME を決める。
  - `.jpg`, `.jpeg` -> `image/jpeg`
  - `.png` -> `image/png`
  - `.webp` -> `image/webp`
  - `.gif` -> `image/gif`
- 未対応拡張子は warning ログを出して空文字列を返す。
- `os.Stat` に失敗した場合は error ログを出して空文字列。
- サイズが 50MB 超なら warning ログを出して空文字列。
- `os.ReadFile` 成功後、`base64.StdEncoding.EncodeToString` し、`data:<mime>;base64,<encoded>` を返す。

### `SanitizeFilename`
- `filepath.Base` でベース名だけを取り出す。
- `..` を除去し、`/` と `\\` を `_` に置換する。
- それ以外の禁止文字や予約名は検査しない。

### `DownloadFile`
- デフォルト値
  - `Timeout == 0` -> 60 秒
  - `LoggerPrefix == ""` -> `"utils"`
- 保存先ディレクトリは `filepath.Join(os.TempDir(), "clawdroid_media")`。
- ディレクトリを `0700` で作成する。
- ローカルファイル名は `<uuid先頭8文字>_<safeName>`。
- `http.NewRequest("GET", url, nil)` を作成し、`ExtraHeaders` をそのまま付与する。
- `http.Client{Timeout: opts.Timeout}` でダウンロードする。
- HTTP ステータスが 200 以外なら失敗。
- 成功時は `os.Create(localPath)` し、`io.Copy` でボディを書き込む。
- 書き込み失敗時はファイルを削除する。
- 正常時は debug ログを出してローカルパスを返す。

### `DownloadFileSimple`
- `LoggerPrefix: "media"` を指定して `DownloadFile` を呼ぶだけの薄いラッパ。

## 入出力・副作用・永続化
### 入力
- ファイルパス、URL、想定ファイル名
- ダウンロードオプション

### 出力
- data URL 文字列または空文字列
- ダウンロードしたローカルパスまたは空文字列

### 副作用
- 一時ディレクトリ作成
- ローカルファイル作成 / 削除
- HTTP リクエスト送信
- `logger.WarnCF`, `logger.ErrorCF`, `logger.DebugCF` によるログ出力

### 永続化
- `os.TempDir()/clawdroid_media/` 配下に一時ファイルを保存する

## 依存関係
- `pkg/logger`
- `github.com/google/uuid`
- 標準ライブラリ: `encoding/base64`, `io`, `net/http`, `os`, `path/filepath`, `strings`, `time`

## エラーハンドリング・制約
- `EncodeFileToDataURL` は画像サイズ上限 50MB を超えると処理しない。
- ダウンロード時に content-type やファイルサイズの検証は行わない。
- `SanitizeFilename` は簡易実装であり、完全なファイル名バリデータではない。
- 失敗時は多くの関数が `error` ではなく空文字列を返す設計である。
