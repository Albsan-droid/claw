# pkg/agent/media.go

## 対象ソース
- `pkg/agent/media.go`

## 概要
このファイルは、エージェント内部で扱うメディアのうち、base64 data URL 形式で届いた画像を永続ファイルへ変換し、不要になったメディアファイルを履歴から掃除する補助処理を提供する。

## 責務
- `data:<mime>;base64,...` 形式の data URL をデコードする
- MIME タイプから保存用拡張子を決定する
- `mediaDir` 配下へファイルを書き込む
- 会話履歴本文中の `[Image: <path>]` 参照を検出して削除する

## 主要な型・関数・メソッド
- `PersistMedia(media []string, mediaDir string) []string`
- `parseDataURL(dataURL string) (ext string, data []byte, err error)`
- `mimeToExt(mime string) string`
- `CleanupMediaFiles(messages []providers.Message)`
- パッケージ変数 `imagePathRe = regexp.MustCompile(`\[Image: ([^\]]+)\]`)`

## 詳細動作
### `PersistMedia`
- `media` が空、または `mediaDir` が空なら `nil` を返す。
- 保存ファイル名の接頭辞は呼び出し時刻の `YYYYMMDD_HHMMSS`。
- 各要素を順に確認し、`data:` で始まらない要素は「すでにファイルパス等」とみなし何もしない。
- `parseDataURL` で拡張子とバイト列を取り出し、`<timestamp>_<index><ext>` で `os.WriteFile(..., 0644)` する。
- 失敗した要素は `logger.WarnCF` を出してスキップし、成功したパスだけ返り値に含める。

### `parseDataURL`
- `data:` 接頭辞が無ければ `not a data URL` を返す。
- 最初のカンマ位置でヘッダと base64 本文を分離する。
- ヘッダ内の `;` より前を MIME として扱い、`mimeToExt` へ渡す。
- 本文は `base64.StdEncoding.DecodeString` でデコードする。

### `mimeToExt`
- 対応 MIME
  - `image/jpeg` -> `.jpg`
  - `image/png` -> `.png`
  - `image/gif` -> `.gif`
  - `image/webp` -> `.webp`
  - `image/bmp` -> `.bmp`
- それ以外は `.bin`

### `CleanupMediaFiles`
- 各 `providers.Message.Content` から正規表現で `[Image: path]` をすべて抽出する。
- 抽出したパスごとに `os.Remove` する。
- `os.IsNotExist(err)` は無視し、それ以外だけ警告ログに残す。

## 入出力・副作用・永続化
### 入力
- data URL 文字列のスライス
- メディア保存先ディレクトリ
- `[Image: path]` を含むメッセージ配列

### 出力
- 保存に成功したファイルパス一覧
- data URL パース結果（拡張子、バイト列、エラー）

### 副作用
- `os.WriteFile` によるバイナリファイル作成
- `os.Remove` によるファイル削除
- `logger.WarnCF` による失敗ログ出力

### 永続化
- `mediaDir` 配下のファイルとして画像が残る
- `CleanupMediaFiles` 実行時に対応ファイルが削除される

## 依存関係
- `pkg/logger`
- `pkg/providers`
- 標準ライブラリ: `encoding/base64`, `fmt`, `os`, `path/filepath`, `regexp`, `strings`, `time`

## エラーハンドリング・制約
- 非 data URL の入力はエラーにせず無視する。
- MIME が未知でも `.bin` で保存は継続する。
- data URL の形式不正や base64 デコード失敗は、その要素だけスキップされる。
- `PersistMedia` は保存先ディレクトリの存在確認や自動作成を行わない。事前に呼び出し側で作成されている前提である。
