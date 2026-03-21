# channels.go 詳細設計

## 対象ソース
- `pkg/constants/channels.go`

## 概要
内部用途のチャネル名を定数集合として定義する。チャネルマネージャや状態管理で、外部向けチャネルと内部処理用チャネルを切り分けるために使われる。

## 責務
- 内部チャネル名の列挙
- 判定用ヘルパーの提供

## 主要な型・関数・メソッド
### `var InternalChannels map[string]bool`
以下のチャネル名を `true` として保持する。
- `cli`
- `system`
- `subagent`

### `IsInternalChannel(channel string) bool`
- `InternalChannels[channel]` をそのまま返す。
- 未定義キーは Go の map 仕様により `false` になる。

## 詳細動作
- `pkg/channels/manager.go` の `dispatchOutbound` では、本関数で内部チャネルを検知すると外部配送を行わず silently skip する。
- コメント上、これらは「外部ユーザーへ露出しない」「last active channel として記録しない」用途を意図している。

## 入出力・副作用・永続化
### 入力
- `channel string`

### 出力
- 内部チャネルなら `true`、それ以外は `false`

### 副作用
- なし

### 永続化
- なし

## 依存関係
- 標準ライブラリ依存なし

## エラーハンドリング・制約
- エラーハンドリングはない。
- 判定は完全一致のみで、大文字小文字の正規化や別名対応はしない。
- `InternalChannels` は可変 map のため、同一プロセス内の他コードから変更可能である。

