# android_media.go 詳細設計

## 対象ソース
- `pkg/tools/android_media.go`

## 概要
メディア再生関連アクションの入力検証を担う。再生/一時停止・次曲・前曲はパラメータ不要であり、音楽検索再生のみ `query` を要求する。

## 責務
- メディアカテゴリのアクションをバリデータへ登録する。
- `play_music_search` の検索語を検証する。

## 主要な型・関数・メソッド
- `init()`
  - `media_play_pause`, `media_next`, `media_previous`, `play_music_search` を登録する。
- `validateMediaParams(action, args)`
  - メディア系アクションの `params` を構築する。

## 詳細動作
- `media_play_pause`
  - パラメータなし。
- `media_next`
  - パラメータなし。
- `media_previous`
  - パラメータなし。
- `play_music_search`
  - `query` を必須とし、非空文字列のみ許可する。

## 入出力・副作用・永続化
### 入力
- `action string`
- `args map[string]interface{}`

### 出力
- `params` または `error`

### 副作用
- `init()` によるカテゴリバリデータ登録。

### 永続化
- なし。

## 依存関係
- `fmt`
- `toString`
- `registerCategoryValidator`

## エラーハンドリング・制約
- `play_music_search` は空クエリを許可しない。
- 再生状態や再生アプリの存在確認はここでは行わない。
