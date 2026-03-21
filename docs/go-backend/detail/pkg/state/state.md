# pkg/state/state.go

## 対象ソース
- `pkg/state/state.go`

## 概要
`state.Manager` は、最後に使ったチャネル / chatID とチャネルごとの chatID 対応表を JSON へ保存する軽量状態ストアである。旧配置から新配置への移行処理も持つ。

## 責務
- 最終利用チャネル・chatID・main client 用チャネルの保持
- チャネル名ごとの最新 chatID マッピング保持
- `state.json` のロード / 保存
- 実ランタイムでは旧 `{dataDir}/state.json` から `{dataDir}/state/state.json` への移行
- 排他制御付き getter / setter 提供

## 主要な型・関数・メソッド
### 型
- `State`
  - `LastChannel string`
  - `LastChatID string`
  - `LastMainChannel string`
  - `ChannelChatIDs map[string]string`
  - `Timestamp time.Time`
- `Manager`
  - `workspace string`
  - `state *State`
  - `mu sync.RWMutex`
  - `stateFile string`

### メソッド・関数
- `NewManager(workspace string) *Manager`
- `SetLastChannel(channel string) error`
- `SetLastChatID(chatID string) error`
- `GetLastChannel() string`
- `GetLastChatID() string`
- `SetLastChannelWithType(channel, clientType string) error`
- `GetLastMainChannel() string`
- `SetChannelChatID(channel, chatID string) error`
- `GetChannelChatID(channel string) string`
- `GetTimestamp() time.Time`
- `saveAtomic() error`
- `load() error`
- `updateChannelChatID(channelKey string)`

## 詳細動作
### 初期化と移行
- `NewManager` の引数名は `workspace` だが、`AgentLoop` は実際には `cfg.DataPath()` を渡しているため、実ランタイムの保存先は dataDir 配下になる。
- `NewManager` は `{baseDir}/state` ディレクトリを `0755` で作成する。
- 新配置 `{baseDir}/state/state.json` が無ければ、旧配置 `{baseDir}/state.json` を読む。
- 旧配置が読み込めて JSON も正しければ `saveAtomic()` で新配置へ保存し、`log.Printf` で移行ログを出す。
- 新配置が存在する場合は `load()` を実行する。

### セッター
- `SetLastChannel`
  - `LastChannel` と `Timestamp` を更新
  - `channel` が `name:chatID` 形式なら `updateChannelChatID` で `ChannelChatIDs[name]=chatID` を更新
  - `saveAtomic()` を呼ぶ
- `SetLastChatID`
  - `LastChatID` と `Timestamp` を更新して保存
- `SetLastChannelWithType`
  - `LastChannel` を更新し、`clientType == "main"` のときは `LastMainChannel` も同時に更新
  - あとは `SetLastChannel` と同様
- `SetChannelChatID`
  - `ChannelChatIDs` が `nil` なら map を初期化
  - 指定チャネルの最新 `chatID` を保存して `Timestamp` を更新

### ゲッター
- すべて read lock 下で値を返す。
- `GetChannelChatID` は map 未初期化時に空文字列を返す。

### 永続化 (`saveAtomic`)
- 保存先は常に `stateFile + ".tmp"`。
- `json.MarshalIndent` した内容を `os.WriteFile(..., 0644)` し、その後 `os.Rename` で本番ファイルへ置換する。
- rename 失敗時は `.tmp` を削除する。
- `fsync` は行わない。

### 読み込み (`load`)
- `os.IsNotExist` は正常系として扱い、空状態のまま返す。
- それ以外の読み込み失敗や JSON 破損は `fmt.Errorf` で wrap して返す。

## 入出力・副作用・永続化
### 入力
- チャネル名、chatID、clientType

### 出力
- 文字列系 getter
- `time.Time`
- setter の `error`

### 副作用
- `state` 構造体の更新
- `state.json` の読み書き
- 移行時の `log.Printf`

### 永続化
- 実ランタイムでは `{dataDir}/state/state.json`
- 保存時一時ファイル: `{dataDir}/state/state.json.tmp`
- ソースコード上のコンストラクタ引数名は `workspace` だが、`pkg/agent/loop.go` からは `dataDir` が渡される

## 依存関係
- 標準ライブラリ: `encoding/json`, `fmt`, `log`, `os`, `path/filepath`, `strings`, `sync`, `time`

## エラーハンドリング・制約
- `updateChannelChatID` は `name:chatID` に `:` が 1 つも無い場合は何もしない。
- `NewManager` は移行・ロード時のエラーを呼び出し元へ返さず、失敗しても空状態で生成される。
- `workspace` フィールドは保持されるが、このファイル内では constructor 以外で直接使っていない。
- パラメータ名と実ランタイムの利用ディレクトリが一致しないため、保存先を確認するときは呼び出し元 (`pkg/agent/loop.go`) も併読する必要がある。
