# pkg/gateway/schema.go 詳細設計

## 対象ソース
- `pkg/gateway/schema.go`

## 概要
`schema.go` は `pkg/config.Config` を反射で走査し、Android フロントエンドが設定 UI を構築するためのスキーマ (`SchemaResponse`) を生成する。`json` タグをキー、`label` タグと `pkg/i18n` を表示名に使い、ネスト構造をドット区切りで平坦化する。

## 責務
- Config 構造体から UI 用スキーマを生成
- Secret / Directory / Calendar など UI 型の補助判定
- `label` タグのローカライズ
- ネスト構造の平坦化とグルーピング

## 主要な型・関数・メソッド
- `type SchemaField struct`
- `type SchemaSection struct`
- `type SchemaResponse struct`
- `var secretKeys map[string]bool`
- `var directoryKeys map[string]bool`
- `var calendarKeys map[string]bool`
- `func BuildSchema(defaultCfg *config.Config, locale string) SchemaResponse`
- `func buildFields(t reflect.Type, v reflect.Value, prefix string, group string, depth int, locale string) []SchemaField`
- `func goTypeToSchema(t reflect.Type) string`
- `func jsonKey(f reflect.StructField) string`
- `func labelTag(f reflect.StructField) string`

## 詳細動作
### 1. スキーマ構造
- `SchemaField`
  - `Key` — ドット区切り設定キー（例: `defaults.workspace`）
  - `Label` — `i18n.T(locale, "config."+labelTag)` の結果
  - `Group` — 親 struct のラベル（生文字列）
  - `Depth` — ネスト深度
  - `Type` — `string` / `bool` / `int` / `float` / `[]string` / `directory` / `calendar` など
  - `Secret` — `secretKeys` による秘匿フラグ
  - `Default` — 既定値
- `SchemaSection` はトップレベル Config フィールド単位のセクションを表す。
- `SchemaResponse` は `Sections []SchemaSection` のみを持つ。

### 2. 特殊キー判定
- `secretKeys`
  - `api_key`, `token`, `bot_token`, `app_token`, `channel_secret`, `channel_access_token`
- `directoryKeys`
  - `defaults.workspace`, `defaults.data_dir`
- `calendarKeys`
  - `calendar_id`
- これらは UI 型上書きや secret マスク判定に使う。

### 3. `BuildSchema()`
- `reflect.TypeOf(defaultCfg).Elem()` と `reflect.ValueOf(defaultCfg).Elem()` を使って `Config` の公開フィールドを列挙する。
- `json` タグが空または `-` のフィールドは無視する。
- トップレベルの `gateway` は「Connection screen 管理」、`version` は内部値として UI から除外する。
- 各セクションのラベルは `i18n.T(locale, "config."+labelTag(field))`。
- `buildFields()` の結果に含まれる `Group` が実質 1 種類以下の場合は、ヘッダ冗長とみなして当該セクション全 field の `Group=""`・`Depth=0` に潰す。

### 4. `buildFields()`
- pointer 型は `Elem()` へ進み、実値があれば `v.Elem()` する。
- 対象型が `struct` でなければ空配列を返す。
- 各公開フィールドについて:
  - `jsonKey()` と `labelTag()` を取得
  - `fullKey` は `prefix + "." + jk` で連結
  - `goTypeToSchema()` の結果が `object` なら再帰し、子グループ名には翻訳前の `rawLabel` を使う
  - `rawLabel == ""` の leaf field は UI 非表示としてスキップする
  - `directoryKeys` / `calendarKeys` に当たれば `Type` を上書きする
- 生成される `Group` は翻訳後ラベルではなく raw label なので、フロントが安定したグループキーとして扱える。

### 5. `goTypeToSchema()`
- `t.Name() == "FlexibleStringSlice"` は明示的に `[]string`
- `reflect.Kind` に応じて `string/bool/int/float/[]string/[]any/map/object/any` を返す

### 6. タグ補助
- `jsonKey()` は `json:"name,omitempty"` のようなタグから `name` 部分だけを返す。
- `labelTag()` は `label` タグをそのまま返す。

## 入出力・副作用・永続化
- 入力
  - `*config.Config` の型情報と既定値
  - `locale`
- 出力
  - `SchemaResponse`
- 永続化
  - なし
- 副作用
  - なし

## 依存関係
- 設定定義: `pkg/config`
- ローカライズ: `pkg/i18n`
- 標準ライブラリ: `reflect`, `strings`

## エラーハンドリング・制約
- 反射処理はエラーを返さず、解釈不能型は `any` または空配列で扱う。
- `BuildSchema()` は `defaultCfg` が `nil` でないことを前提とする。
- `label` タグが空の leaf field は UI に出ない。
- `directoryKeys` はフルキー、`secretKeys` / `calendarKeys` は単一キーで判定しているため、キー名の衝突に注意が必要。
