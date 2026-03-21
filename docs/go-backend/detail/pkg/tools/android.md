# android.go 詳細設計

## 対象ソース
- `pkg/tools/android.go`

## 概要
`AndroidTool` は Go バックエンド側の Android ツール本体であり、LLM から渡された `action` と引数を検証し、WebSocket 経由で Android クライアントへ `tool_request` を送信し、その応答を待って `ToolResult` に変換する。

## 責務
- Android ツールのメタ情報 (`Name` / `Description` / `Parameters`) を提供する。
- 実行時コンテキスト (`channel`, `chatID`, `clientType`) と送信コールバックを保持する。
- コアアクションおよびカテゴリ別アクションの入力検証を行う。
- 設定値に基づくカテゴリ単位・アクション単位の有効/無効判定を行う。
- `tool_request` と `tool_response` の対応付けを `DeviceResponseWaiter` で管理する。
- スクリーンショットや `accessibility_required` などの特殊応答を `ToolResult` に整形する。

## 主要な型・関数・メソッド
### 型
- `SendCallbackWithType`
  - `func(channel, chatID, content, msgType string) error`
  - WebSocket 等の下位チャネルへメッセージを送るコールバック。
- `toolRequest`
  - Android 側へ送る JSON ペイロード。
  - `request_id`, `action`, `params` を持つ。
- `AndroidTool`
  - 実行設定 (`cfg`)、送信コールバック、接続コンテキストを保持する本体。

### 定数・変数
- `androidToolTimeout = 15 * time.Second`
  - 応答待機の固定タイムアウト。
- `packageNameRe`
  - パッケージ名の書式検証用正規表現。
- `intentActionRe`
  - `intent_action` の書式検証用正規表現。
- `categoryValidators`
  - カテゴリ別ファイルが `init()` で登録する検証関数テーブル。

### 関数・メソッド
- `NewAndroidTool(cfg)`
  - 設定を保持した `AndroidTool` を生成する。
- `(t *AndroidTool) Name()`
  - 常に `"android"` を返す。
- `(t *AndroidTool) SetClientType(ct)`
  - `main` クライアントかどうかを記録する。`main` は UI 操作アクションを隠す。
- `(t *AndroidTool) Description()`
  - `enabledActions` と `buildDescription` を用いて動的な説明文を返す。
- `(t *AndroidTool) Parameters()`
  - 有効アクションだけを含む JSON Schema 風の引数定義を返す。
- `(t *AndroidTool) SetContext(channel, chatID)`
  - Android 端末へ送信する対象チャネルを設定する。
- `(t *AndroidTool) SetSendCallback(cb)`
  - 送信処理を注入する。
- `(t *AndroidTool) Execute(ctx, args)`
  - 入力検証→有効判定→パラメータ構築→送信待機までの主経路。
- `(t *AndroidTool) validateAndBuildParams(action, args)`
  - コアアクションの引数検証とカテゴリ別バリデータへの委譲を行う。
- `(t *AndroidTool) sendAndWait(ctx, action, params)`
  - `request_id` を採番し、JSON 送信後に `DeviceResponseWaiter` で応答を待つ。
- `registerCategoryValidator(fn, actions...)`
  - 各カテゴリファイルの `init()` から呼ばれ、`categoryValidators` を初期化する。
- `(t *AndroidTool) isActionEnabled(action)`
  - カテゴリ有効化 + 個別アクション有効化の両方を確認する。
- `isUIAction(action)`
  - UI 専用アクションかどうかを返す。
- `validateIntentExtras(extras)`
  - `intent_extras` の値がプリミティブ型のみか検証する。
- `toInt` / `toString` / `toBool` / `toFloat64`
  - JSON 由来の `interface{}` から値を安全に取り出す補助関数。

## 詳細動作
### 1. 実行前提の確認
`Execute` は以下を順に確認する。
1. `sendCallback` が設定済みであること。
2. `channel` と `chatID` が空でないこと。
3. `args["action"]` が文字列として与えられていること。
4. `isActionEnabled(action)` が真であること。
5. `clientType == "main"` の場合、UI 専用アクションではないこと。

無効なアクションや禁止アクションに対しては、存在自体を隠すため `unknown action: <action>` を返す。

### 2. パラメータ検証
`validateAndBuildParams` はアクション別に `params` を構築する。
- `search_apps`: `query` 必須。
- `app_info`, `launch_app`: `package_name` 必須。`packageNameRe` に一致する必要がある。
- `screenshot`: パラメータなし。
- `get_ui_tree`:
  - `resource_id` と `bounds_x`/`bounds_y` は排他。
  - `index` は 0 以上。
  - `max_nodes` は 1 以上。
- `tap`: `x`, `y` 必須。
- `swipe`: `x`, `y`, `x2`, `y2` 必須。`duration_ms` は任意。
- `text`: `text` 必須。
- `keyevent`: `key` 必須。許可値は `back`, `home`, `recents`。
- `broadcast`:
  - `intent_action` 必須。
  - `intent_extras` は `validateIntentExtras` で検証。
- `intent`:
  - `intent_action` 必須。
  - `intent_package` は Android パッケージ名書式である必要がある。
  - `intent_extras` はプリミティブ値のみ許可。
- その他のアクション:
  - `categoryValidators[action]` があればカテゴリ別実装へ委譲する。
  - カレンダーカテゴリの場合、戻り値に `calendar_id` がなければ `cfg.Calendar.CalendarID` を注入する。

### 3. 送信と応答待機
`sendAndWait` の流れは以下の通り。
1. `uuid.New().String()` で `request_id` を採番する。
2. `toolRequest` を JSON 化する。
3. 送信前に `DeviceResponseWaiter.Register(requestID)` を呼び、応答チャネルを事前登録する。
4. `sendCallback(..., "tool_request")` で Android 側へ送信する。
5. 以下の 3 パターンを `select` で待つ。
   - 応答受信
   - 15 秒タイムアウト
   - `ctx.Done()` によるキャンセル

### 4. 応答の整形
- 応答文字列が `accessibility_required` で始まる場合:
  - `ForUser` は日本語メッセージ。
  - `ForLLM` は再試行禁止の説明付きメッセージ。
- `action == "screenshot"` の場合:
  - 応答文字列を Base64 JPEG とみなし、`data:image/jpeg;base64,` を付与して `Media` に入れる。
  - `Silent: true` を立てる。
- それ以外:
  - `SilentResult(content)` を返す。

## 入出力・副作用・永続化
### 入力
- `context.Context`
- `map[string]interface{}` 形式の引数
- 事前設定された `channel`, `chatID`, `clientType`, `cfg`, `sendCallback`

### 出力
- `*ToolResult`
  - 正常時はサイレント結果またはスクリーンショットのマルチモーダル結果。
  - 異常時は `ErrorResult(...)`。

### 副作用
- WebSocket 相当の送信コールバックを呼ぶ。
- `DeviceResponseWaiter` に待機チャネルを登録・削除する。

### 永続化
- このファイル単体ではファイル保存や DB 更新は行わない。

## 依存関係
- `github.com/KarakuriAgent/clawdroid/pkg/config`
  - `AndroidToolsConfig` を保持し、有効/無効判定に使う。
- `github.com/google/uuid`
  - `request_id` 採番に使用。
- `pkg/tools/response_waiter.go`
  - `DeviceResponseWaiter` を用いた応答同期。
- `ToolResult`, `ErrorResult`, `SilentResult`
  - 同一 `tools` パッケージ内の結果表現に依存する。
- `android_actions.go` および各 `android_*.go`
  - アクション一覧・カテゴリ別バリデーションに依存する。

## エラーハンドリング・制約
- `sendCallback` 未設定時は `android tool: send callback not configured`。
- コンテキスト未設定時は `android tool: no active channel context`。
- 不正/無効/禁止アクションは `unknown action` として扱う。
- `package_name`, `intent_action`, `intent_package` は正規表現制約を持つ。
- `intent_extras` は文字列・数値・真偽値・`nil` のみ許可し、配列やネストしたオブジェクトは拒否する。
- タイムアウト時は `DeviceResponseWaiter.Cleanup` を呼んでリークを防止する。
- `ctx.Done()` でも待機を解除する。
