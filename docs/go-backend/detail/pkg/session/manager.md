# pkg/session/manager.go

## 対象ソース
- `pkg/session/manager.go`

## 概要
`SessionManager` は会話履歴と会話サマリーをセッション単位で保持し、必要に応じて JSON ファイルへ保存する。メモリ内キャッシュとファイル永続化を併用する構成である。

## 責務
- セッションの生成・取得
- メッセージ履歴の追加・取得・置換・切り詰め
- 会話サマリーの取得・更新
- セッションの JSON 保存と起動時ロード
- 同時アクセスの排他制御

## 主要な型・関数・メソッド
### 型
- `Session`
  - `Key string`
  - `Messages []providers.Message`
  - `Summary string`
  - `Created time.Time`
  - `Updated time.Time`
- `SessionManager`
  - `sessions map[string]*Session`
  - `mu sync.RWMutex`
  - `storage string`

### メソッド・関数
- `NewSessionManager(storage string) *SessionManager`
- `GetOrCreate(key string) *Session`
- `AddMessage(sessionKey, role, content string)`
- `AddFullMessage(sessionKey string, msg providers.Message)`
- `GetHistory(key string) []providers.Message`
- `GetSummary(key string) string`
- `SetSummary(key string, summary string)`
- `TruncateHistory(key string, keepLast int)`
- `Save(key string) error`
- `SetHistory(key string, history []providers.Message)`
- `loadSessions() error`
- `sanitizeFilename(key string) string`

## 詳細動作
### 初期化
- `NewSessionManager` は `storage` が空でなければ `os.MkdirAll(storage, 0755)` を行い、`loadSessions()` で既存 JSON を読む。
- `storage` が空なら永続化を無効化したメモリ専用マネージャになる。

### セッション生成と更新
- `GetOrCreate` は存在しなければ空履歴の `Session` を生成する。
- `AddMessage` は簡易ラッパで、内部では `AddFullMessage` を使う。
- `AddFullMessage` は未作成セッションも自動生成し、`Updated` を現在時刻に更新する。
- `SetSummary` と `SetHistory` は **既存セッションにしか作用しない**。未作成キーは黙って無視する。
- `TruncateHistory`
  - `keepLast <= 0` のとき履歴を空にする
  - 履歴長が十分短い場合は何もしない
  - それ以外は末尾 `keepLast` 件だけ残す

### 履歴取得
- `GetHistory` は `providers.Message` スライスのコピーを返す。
- ただし各 `providers.Message` のネストしたスライス (`Media`, `ToolCalls`) までは再コピーしない。

### ファイル名と保存
- `sanitizeFilename` は `:` を `_` に置き換えるだけ。
- `Save`
  - `storage==""` なら何もしない
  - ファイル名に対し `filepath.IsLocal` と `strings.ContainsAny(filename, "/\\")` を用いて妥当性検査する
  - セッションスナップショットを read lock 下でコピーし、I/O はロック外で行う
  - `os.CreateTemp(storage, "session-*.tmp")` で一時ファイルを作る
  - `Write` -> `Chmod(0644)` -> `Sync` -> `Close` -> `Rename` の順で保存する

### 起動時ロード
- `loadSessions` は `storage` 直下の `.json` ファイルだけを対象に読む。
- JSON の中にある `session.Key` を map のキーに使うため、ファイル名から逆算はしない。
- 読み込み失敗や JSON 破損はそのファイルだけスキップする。

## 入出力・副作用・永続化
### 入力
- セッションキー
- `providers.Message`
- summary 文字列
- history 配列

### 出力
- `*Session`
- 履歴コピー `[]providers.Message`
- `error`

### 副作用
- `sessions` マップ更新
- JSON ファイル I/O
- `sync.RWMutex` による排他

### 永続化
- `storage/<sanitized-key>.json`
- 保存時は同ディレクトリ内の一時ファイルを経由する

## 依存関係
- `pkg/providers`
- 標準ライブラリ: `encoding/json`, `os`, `path/filepath`, `strings`, `sync`, `time`

## エラーハンドリング・制約
- 保存ファイル名検証に失敗すると `os.ErrInvalid` を返す。
- `Save` は存在しないセッションキーに対しては `nil` を返して何もしない。
- `GetOrCreate` は内部セッションへのポインタを返すため、外部で直接変更すると排他制御を迂回できる。
