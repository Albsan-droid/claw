# broadcast.go 詳細設計

## 対象ソース
- `pkg/broadcast/broadcast.go`

## 概要
Android 端末上のアプリへ `am broadcast` を使ってメッセージを通知するための補助機能である。Go バックエンドが Termux 上で同一端末内に存在する前提で、WebSocket 切断時のフォールバック経路として使われる。

## 責務
- Android broadcast 用ペイロードの JSON 化
- `am broadcast` サブプロセスの起動
- 実行失敗時のログ出力

## 主要な型・関数・メソッド
### 定数
- `Action = "io.clawdroid.AGENT_MESSAGE"`
  - Android 側で待ち受ける intent action
- `Package = "io.clawdroid"`
  - 送信先パッケージ名

### `type Message struct`
- `Content string`
- `Type string`

### `Send(msg Message) error`
- `Message` を JSON 文字列へ変換する。
- `am broadcast -a <Action> -p <Package> --es message <json>` を実行する。
- 成功時は content 長をログ出力する。
- 失敗時は標準出力/標準エラーを含めてログし、ラップした `error` を返す。

## 詳細動作
1. `json.Marshal(msg)` でペイロードを作成する。
2. `exec.Command` で `am broadcast` コマンドを構築する。
3. `CombinedOutput()` で実行し、終了まで待つ。
4. 失敗時は `logger.ErrorCF` で `error` と `output` を記録する。
5. 成功時は `logger.InfoCF` で `content_len` を記録する。

## 入出力・副作用・永続化
### 入力
- `Message{Content, Type}`

### 出力
- 成功時 `nil`
- 失敗時 `error`

### 副作用
- OS プロセス起動 (`am`)
- Android への broadcast 送信
- ログ出力

### 永続化
- なし

## 依存関係
- `encoding/json`
- `fmt`
- `os/exec`
- `github.com/KarakuriAgent/clawdroid/pkg/logger`

## エラーハンドリング・制約
- JSON 変換に失敗すると即座に `error` を返す。
- `am` コマンドが存在しない、権限不足、Android 側未導入などの実行時問題は `CombinedOutput` の失敗として返る。
- リトライやタイムアウト制御は実装していない。
- 端末内 Android 環境を前提としており、一般的な Linux 実行環境では成功しない可能性が高い。

