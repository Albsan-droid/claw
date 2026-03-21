# android_navigation.go 詳細設計

## 対象ソース
- `pkg/tools/android_navigation.go`

## 概要
地図・ナビゲーション系アクションの入力検証を行う。目的地、検索語、地図表示条件、移動手段列挙値などを確認し、Android 側実装へ渡す `params` を整形する。

## 責務
- ナビゲーションカテゴリのアクションを登録する。
- 目的地や検索語の必須性、`mode` の列挙値、座標の組み合わせ条件を検証する。

## 主要な型・関数・メソッド
- `init()`
  - `navigate`, `search_nearby`, `show_map`, `get_current_location` を登録する。
- `validateNavigationParams(action, args)`
  - アクション別検証を行う。

## 詳細動作
- `navigate`
  - `destination` 必須。
  - `mode` が指定される場合は `driving`, `walking`, `bicycling`, `transit` のいずれかのみ許可。
- `search_nearby`
  - `query` 必須。
- `show_map`
  - `query` または `latitude`+`longitude` のどちらかを必須とする。
  - `query` があればそのまま格納。
  - `latitude` と `longitude` が両方ある場合のみ座標を格納。
- `get_current_location`
  - パラメータなし。

## 入出力・副作用・永続化
### 入力
- `action string`
- `args map[string]interface{}`

### 出力
- `params` または `error`

### 副作用
- `init()` でカテゴリバリデータを登録する。

### 永続化
- なし。

## 依存関係
- `fmt`
- `toString`, `toFloat64`
- `registerCategoryValidator`

## エラーハンドリング・制約
- `show_map` は緯度だけ・経度だけの片方指定を受け付けない。
- 緯度経度の範囲 (`-90〜90`, `-180〜180`) はこのファイルでは検証しない。
- `navigate` の `mode` は未指定可だが、指定時は列挙値以外を拒否する。
