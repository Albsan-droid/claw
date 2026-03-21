# pkg/agent/users.go

## 対象ソース
- `pkg/agent/users.go`

## 概要
`UserStore` は `users.json` を通じてユーザーディレクトリを管理する。ユーザー名、チャネルごとの識別子、メモを保持し、ツール層で使う `tools.UserDirectory` へのアダプタも提供する。

## 責務
- `users.json` のロード / セーブ
- legacy `USER.md` の移行要否判定
- ユーザーの作成・更新・削除
- チャネル ID の関連付けと逆引き
- ユーザーメモの追加・削除
- `tools.UserDirectory` インターフェースへの橋渡し

## 主要な型・関数・メソッド
### 型
- `User`
  - `ID string`
  - `Name string`
  - `Channels map[string][]string`
  - `Memo []string`
- `usersFile`
  - `Users []*User`
- `UserStore`
  - `mu sync.RWMutex`
  - `dataDir`, `filePath`
  - `users []*User`
  - `needsMigration bool`
- `userStoreAdapter`
  - `store *UserStore`

### 主要関数・メソッド
- `NewUserStore(dataDir string) *UserStore`
- `NeedsMigration() bool`
- `LegacyFilePath() string`
- `ResolveByChannelID(channel, senderID string) *User`
- `Get(userID string) *User`
- `List() []*User`
- `Create(name, channel, channelID string) (*User, error)`
- `Update(userID, name string) error`
- `Link(userID, channel, channelID string) error`
- `AddMemo(userID, memo string) error`
- `RemoveMemo(userID string, index int) error`
- `Delete(userID string) error`
- `AsDirectory() tools.UserDirectory`
- 補助: `load`, `save`, `generateUserID`, `findByID`, `userToInfo`

## 詳細動作
### 初期化と移行判定
- `NewUserStore` は `dataDir/users.json` を対象とする。
- `users.json` が存在せず、`dataDir/USER.md` が存在する場合だけ `needsMigration=true` にする。
- 実際の移行処理はこのファイルでは行わず、フラグ提示だけを担当する。

### ロード / セーブ
- `load` は `users.json` を読めなければ空配列で初期化する。
- JSON が壊れていてもエラーは返さず空配列に戻す。
- `save` は `users.json.tmp` に JSON を書いてから `os.Rename` する原子的更新方式を使う。

### ID 生成
- `generateUserID` は 6 バイトの乱数を `hex.EncodeToString` し、`u_` を前置する。
- `rand.Read` のエラーは無視される。

### 検索系
- `ResolveByChannelID`
  - 指定チャネルの `Channels[channel]` を持つユーザーを順に探索する。
  - `channel == "websocket"` の場合は `senderID` を無視し、そのチャネルが設定された最初のユーザーを返す。
- `Get` は内部ポインタをそのまま返す。
- `List` はスライスの shallow copy を返すが、各 `*User` 自体は共有される。

### 更新系
- `Create`
  - WebSocket は排他的で、既に誰かに紐づいていればエラー
  - WebSocket の `channelID` は意味を持たないため常に `"linked"` に正規化
  - 生成後に `save` し、失敗時は append を巻き戻す
- `Update`
  - `name != ""` のときだけ上書きする
- `Link`
  - WebSocket は `Create` と同じく排他的で、他ユーザーに紐づいていればエラー
  - WebSocket 以外は重複 ID を追加しない
- `AddMemo`
  - メモ末尾に追加して保存
- `RemoveMemo`
  - インデックス境界チェック後に削除して保存
- `Delete`
  - スライスから対象ユーザーを除去して保存

### ツールアダプタ
- `AsDirectory` は `userStoreAdapter` を返す。
- アダプタは `tools.UserInfo` へ変換するだけで、実際の処理は `UserStore` に委譲する。

## 入出力・副作用・永続化
### 入力
- ユーザー名、`userID`、チャネル名、チャネル ID、メモ本文、メモインデックス

### 出力
- `*User` / `[]*User`
- `tools.UserDirectory`
- 更新系の `error`

### 副作用
- `users.json` の読み書き
- 内部ユーザースライスの更新
- `sync.RWMutex` による排他制御

### 永続化
- `dataDir/users.json`
- 一時ファイル `dataDir/users.json.tmp` を経由して更新

## 依存関係
- `pkg/tools`
- 標準ライブラリ: `crypto/rand`, `encoding/hex`, `encoding/json`, `fmt`, `os`, `path/filepath`, `sync`

## エラーハンドリング・制約
- 見つからない `userID` は `errUserNotFound` を wrap して返す。
- `RemoveMemo` は範囲外インデックスでエラーを返す。
- WebSocket は常に 1 ユーザーにのみリンクできる。
- `Get` / `List` が返す `User` ポインタは内部構造を指すため、呼び出し側が直接書き換えるとロック外変更になりうる。
