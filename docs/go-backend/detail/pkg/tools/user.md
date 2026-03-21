# pkg/tools/user.go 詳細設計

## 対象ソース
- `pkg/tools/user.go`

## 概要
ユーザーディレクトリの CRUD、チャネル紐付け、メモ管理、旧 `USER.md` 互換運用を 1 つのツールへまとめた実装である。保存処理は `UserDirectory` に委譲し、本ファイルは action 分岐と結果整形を担当する。

## 責務
- ユーザー一覧取得・単体取得・作成・更新・削除を提供する。
- チャネル ID 紐付け (`link`) を提供する。
- ユーザーメモの追加・削除を提供する。
- レガシー `USER.md` の読み取りと削除をサポートする。

## 主要な型・関数・メソッド
### `type UserDirectory interface`
- `List`, `Get`, `Create`, `Update`, `Delete`, `Link`, `AddMemo`, `RemoveMemo`, `LegacyFilePath`

### `type UserInfo`
- `ID`, `Name`, `Channels map[string][]string`, `Memo []string`

### `type UserTool`
- フィールド: `dir UserDirectory`, `hasLegacyFile bool`
- `NewUserTool(dir UserDirectory, hasLegacyFile bool) *UserTool`
- `Execute(ctx, args) *ToolResult`

### 補助関数・内部メソッド
- `requireString(args, key, action)`
- `execList`, `execGet`, `execCreate`, `execUpdate`, `execDelete`, `execLink`, `execAddMemo`, `execRemoveMemo`, `execReadLegacy`, `execDeleteLegacy`

## 詳細動作
- `Description` と `Parameters` の action enum は `hasLegacyFile` に応じて `read_legacy` / `delete_legacy` を増減させる。
- `Execute` は action ごとに内部メソッドへ委譲する。
- 一覧・単体取得・作成では `json.MarshalIndent` を使い、整形済み JSON を `SilentResult` で返す。
- `memo_index` は JSON 数値として `float64` で受け、`int` へキャストして `RemoveMemo` に渡す。
- `execReadLegacy` は `USER.md` 内容に加え、移行手順ガイド文をまとめて返す。
- `execDeleteLegacy` は実際に `os.Remove` を行った後、`hasLegacyFile=false` に切り替える。

## 入出力・副作用・永続化
- 入力: `action`, `user_id`, `name`, `channel`, `channel_id`, `memo`, `memo_index`
- 出力: 整形 JSON、説明文、またはエラー結果。
- 副作用: ユーザーストア更新、旧 `USER.md` ファイル削除・読み込み。
- 永続化: `UserDirectory` 実装とファイルシステムに委譲される。

## 依存関係
- 標準ライブラリ: `context`, `encoding/json`, `fmt`, `os`
- 同一パッケージ: `SilentResult`, `ErrorResult`
- 実装想定: コメント上は `agent.UserStore`

## エラーハンドリング・制約
- 必須文字列は `requireString` で統一検証する。
- 未知 action はエラー。
- `memo_index` は数値型前提で、文字列入力は受け付けない。
- `hasLegacyFile` は `UserTool` 内部状態であり、外部ストア状態と自動同期はされない。
