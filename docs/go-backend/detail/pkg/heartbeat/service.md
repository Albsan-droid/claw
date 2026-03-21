# service.go 詳細設計

## 対象ソース
- `pkg/heartbeat/service.go`

## 概要
`HeartbeatService` は一定間隔で `HEARTBEAT.md` を読み込み、そこから構築したプロンプトをハンドラへ渡して定期タスクを実行するサービスである。結果はメッセージバス経由で最後に利用されたユーザーチャネルへ返送できる。

## 責務
- ハートビート間隔と有効/無効状態を管理する。
- バックグラウンド ticker で定期実行する。
- `HEARTBEAT.md` からプロンプトを構築し、未存在時はテンプレートを生成する。
- 最後に使われたユーザーチャネルを `state.Manager` から取得する。
- ハンドラ結果 (`ToolResult`) を評価し、必要ならメッセージバスへ送信する。
- `heartbeat.log` に独自ログを書き込む。

## 主要な型・関数・メソッド
### 定数
- `minIntervalMinutes = 5`
- `defaultIntervalMinutes = 30`

### 型
- `HeartbeatHandler`
  - `func(prompt, channel, chatID string) *tools.ToolResult`
- `HeartbeatService`
  - `workspace`, `dataDir`, `bus`, `state`, `handler`, `interval`, `enabled`, `mu`, `stopChan` を保持する。

### 関数・メソッド
- `NewHeartbeatService(workspace, dataDir, intervalMinutes, enabled, stateManager)`
- `(hs *HeartbeatService) SetBus(msgBus)`
- `(hs *HeartbeatService) SetHandler(handler)`
- `(hs *HeartbeatService) Start()` / `Stop()` / `IsRunning()`
- `(hs *HeartbeatService) runLoop(stopChan)`
- `(hs *HeartbeatService) executeHeartbeat()`
- `(hs *HeartbeatService) buildPrompt()`
- `(hs *HeartbeatService) createDefaultHeartbeatTemplate()`
- `(hs *HeartbeatService) sendResponse(response)`
- `(hs *HeartbeatService) parseLastChannel(lastChannel)`
- `(hs *HeartbeatService) logInfo(...)` / `logError(...)` / `log(...)`

## 詳細動作
### 1. 生成時の設定補正
`NewHeartbeatService` は以下を適用する。
- `intervalMinutes < 5` かつ 0 以外なら 5 分へ切り上げ。
- `intervalMinutes == 0` なら既定 30 分。
- `stateManager == nil` なら `state.NewManager(dataDir)` を内部生成。
- `workspace` は構造体に保存されるが、このファイル内では現在利用していない。

### 2. 起動・停止
- `Start`
  - 既に `stopChan != nil` なら多重起動を避けて終了。
  - `enabled == false` なら起動しない。
  - `stopChan` を作成し、`runLoop` を goroutine 起動する。
  - 共通ロガー `logger.InfoC/InfoCF` へ開始ログを出す。
- `Stop`
  - `stopChan` を close して `nil` に戻す。
- `IsRunning`
  - `stopChan != nil` で判定する。

### 3. 周期実行
`runLoop` は `time.NewTicker(hs.interval)` を作成し、以下を待つ。
- `stopChan` 受信で終了。
- `ticker.C` 受信で `executeHeartbeat()` 実行。

### 4. ハートビート本体
`executeHeartbeat` の流れ:
1. 読み取りロックで `enabled`, `handler`, `stopChan` を確認し、無効・停止済みなら終了。
2. `buildPrompt()` でプロンプトを生成する。空文字なら実行しない。
3. `handler == nil` ならエラーログを書いて終了。
4. `state.GetLastMainChannel()` を優先し、空なら `state.GetLastChannel()` を後方互換として使う。
5. `parseLastChannel` で `(channel, chatID)` に分解する。
6. `handler(prompt, channel, chatID)` を呼ぶ。
7. 返却された `ToolResult` を以下の優先順で処理する。
   - `nil`: 情報ログのみ。
   - `IsError`: エラーログのみ。
   - `Async`: 起動ログのみ。
   - `Silent`: 成功ログのみでユーザー通知しない。
   - それ以外: `ForUser` 優先、空なら `ForLLM` を `sendResponse` で送る。

### 5. プロンプト構築
`buildPrompt` は `dataDir/HEARTBEAT.md` を読む。
- ファイル未存在時:
  - `createDefaultHeartbeatTemplate()` を呼ぶ。
  - その回の実行は空文字を返してスキップ。
- 読み取りエラー時:
  - エラーログを書き、空文字を返す。
- 空ファイル時:
  - 空文字を返す。
- 非空時:
  - 現在時刻 (`2006-01-02 15:04:05 MST`) を埋め込んだハートビート用プロンプトを返す。

### 6. デフォルトテンプレート生成
`createDefaultHeartbeatTemplate` は `HEARTBEAT.md` にサンプル内容を書き込む。ファイル権限は `0644`。
内容には以下の運用ルールが含まれる。
- すべてのタスクを実行すること。
- 複雑な処理は subagent/spawn を使うこと。
- すべて完了し何も問題がなければ `HEARTBEAT_OK` だけ返すこと。

### 7. 応答送信
`sendResponse` は `bus.MessageBus` が設定済みか確認し、最後のチャネルを再解決して `bus.OutboundMessage` を publish する。
- 送信先チャネル解決でも `GetLastMainChannel` を優先する。
- 内部チャネルや不正形式は `parseLastChannel` で除外される。

### 8. チャネル文字列解析
`parseLastChannel` は `platform:user_id` 形式を `strings.SplitN(..., ":", 2)` で分解する。
- 形式不正ならエラーログを書き、空文字列を返す。
- `constants.IsInternalChannel(platform)` が真なら通知対象外として空文字列を返す。

### 9. ログ出力
`log` は `dataDir/heartbeat.log` を `os.O_APPEND|os.O_CREATE|os.O_WRONLY` で開き、`[timestamp] [LEVEL] message` 形式で 1 行追記する。ファイル権限は `0644`。

## 入出力・副作用・永続化
### 入力
- `workspace`, `dataDir`
- 間隔分数 `intervalMinutes`
- 有効フラグ `enabled`
- 任意の `state.Manager`, `bus.MessageBus`, `HeartbeatHandler`

### 出力
- `Start()` は `error` を返すが、現実装では通常成功パスのみ。
- `IsRunning()` は `bool`。
- ハンドラ実行結果は必要に応じてユーザー向けメッセージ送信に変換される。

### 副作用
- goroutine と ticker を起動する。
- `HEARTBEAT.md` が無ければ新規作成する。
- `heartbeat.log` に追記する。
- `MessageBus.PublishOutbound` で外向きメッセージを配信する。

### 永続化
- `dataDir/HEARTBEAT.md`
  - 未存在時にテンプレート生成。
- `dataDir/heartbeat.log`
  - 実行ログを追記。

## 依存関係
- `github.com/KarakuriAgent/clawdroid/pkg/bus`
  - 応答メッセージ送信に使用する。
- `github.com/KarakuriAgent/clawdroid/pkg/constants`
  - 内部チャネル判定に使用する。
- `github.com/KarakuriAgent/clawdroid/pkg/logger`
  - サービス開始/停止や async 実行の共通ログ出力に使用する。
- `github.com/KarakuriAgent/clawdroid/pkg/state`
  - 最後のユーザーチャネル取得に使用する。
- `github.com/KarakuriAgent/clawdroid/pkg/tools`
  - `ToolResult` 型参照。
- `os`, `filepath`, `strings`, `sync`, `time`, `fmt`

## エラーハンドリング・制約
- `Start` は既に起動済み・無効状態でもエラーを返さず終了する。
- `buildPrompt` のファイル未存在はエラー扱いせず、テンプレート作成後にその回の実行をスキップする。
- `handler` 未設定時はログのみでユーザー通知しない。
- 内部チャネルや不正チャネル形式には送信しない。
- `sendResponse` は `bus` 未設定・チャネル未記録時も静かに終了する。
- `log` でログファイルを開けない場合、追加のエラーは返さず黙って失敗する。
