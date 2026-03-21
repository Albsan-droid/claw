# types.go 詳細設計

## 対象ソース
- `pkg/bus/types.go`

## 概要
`pkg/bus/types.go` は、メッセージバス上を流れる受信・送信データ構造とハンドラ型を定義する。チャネル実装と内部処理の契約面を担う定義ファイルであり、ロジックは持たない。

## 責務
- 受信メッセージ形式の定義
- 送信メッセージ形式の定義
- ハンドラ関数シグネチャの定義
- JSON シリアライズ時のキー名の固定

## 主要な型・関数・メソッド
### `type InboundMessage struct`
チャネルからバックエンド内部へ流す入力メッセージ。
- `Channel string`
  - どのチャネルから来たかを示す論理名
- `SenderID string`
  - 送信者識別子。チャネルごとに形式が異なる
- `ChatID string`
  - 会話単位の識別子
- `Content string`
  - テキスト本文
- `Media []string`
  - 添付メディア。Data URL、ローカルパス等を格納し得る
- `SessionKey string`
  - セッション識別子。通常は `channel:chatID`
- `Metadata map[string]string`
  - チャネル固有補足情報

### `type OutboundMessage struct`
内部処理からチャネルへ返す出力メッセージ。
- `Channel string`
  - 配送先チャネル名
- `ChatID string`
  - 配送先会話 ID
- `Content string`
  - 送信本文
- `Type string`
  - 任意種別。コメント上は `"message"`(空時の既定), `"status"`, `"error"` を想定

### `type MessageHandler func(InboundMessage) error`
- 受信メッセージ 1 件を処理する関数型
- 呼び出し側が `error` を解釈できるようにしている

## 詳細動作
- 本ファイル自体に処理フローはない。
- `InboundMessage` は各チャネル実装から `MessageBus.PublishInbound` に流される前提で構成されている。
- `OutboundMessage` は内部処理から `MessageBus.PublishOutbound` に流され、`Manager.dispatchOutbound` で配送される前提で構成されている。
- `Metadata` により、チャネル固有の ID・ロケール・スレッド情報などを追加できる。

## 入出力・副作用・永続化
### 入力
- なし（型定義のみ）

### 出力
- なし（型定義のみ）

### 副作用
- なし

### 永続化
- なし

## 依存関係
- 標準ライブラリ依存なし
- 他パッケージから参照される共有契約として利用される

## エラーハンドリング・制約
- バリデーションロジックは持たないため、空文字や不正フォーマットの制御は利用側に委ねられる。
- `Type` の許容値はコメントで示されるのみで、型レベル制約はない。
- `Metadata` のキー体系も固定されておらず、チャネル実装ごとに意味が異なる。

