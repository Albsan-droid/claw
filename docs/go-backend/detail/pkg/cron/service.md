# service.go 詳細設計

## 対象ソース
- `pkg/cron/service.go`

## 概要
`CronService` は JSON ストアに保存されたジョブ定義を読み込み、次回実行時刻を計算し、バックグラウンド goroutine で時刻監視を行い、期日到来時にコールバック `onJob` を実行する永続化付きスケジューラである。

## 責務
- ジョブ定義のロード・保存を `storePath` 上の JSON ファイルで行う。
- `at` / `every` / `cron` の 3 種類のスケジュールから次回実行時刻を計算する。
- 最も近いジョブ時刻まで待機し、到来したジョブを順次実行する。
- 実行結果をジョブ状態 (`LastRunAtMS`, `LastStatus`, `LastError`, `NextRunAtMS`) に反映する。
- ジョブ追加・更新・削除・有効化/無効化・一覧取得・状態取得 API を提供する。

## 主要な型・関数・メソッド
### 型
- `CronSchedule`
  - `Kind`: `at` / `every` / `cron`
  - `AtMS`, `EveryMS`, `Expr`, `TZ`
- `CronPayload`
  - 現在は `Kind`, `Message`, `Command`, `Deliver`, `Channel`, `To` を保持する。
- `CronJobState`
  - 実行状態 (`NextRunAtMS`, `LastRunAtMS`, `LastStatus`, `LastError`) を保持する。
- `CronJob`
  - ジョブ本体。`DeleteAfterRun` によりワンショット削除可否を持つ。
- `CronStore`
  - JSON ストアのルート。`Version` と `Jobs` を持つ。
- `JobHandler`
  - `func(job *CronJob) (string, error)`
- `CronService`
  - ストア、コールバック、排他制御、実行ループ制御チャネル、`gronx` インスタンスを保持する。

### 関数・メソッド
- `NewCronService(storePath, onJob)`
- `(cs *CronService) Start()` / `Stop()`
- `(cs *CronService) runLoop(stopChan, rescheduleCh)`
- `(cs *CronService) notifyReschedule()`
- `(cs *CronService) checkJobs()`
- `(cs *CronService) executeJobByID(jobID)`
- `(cs *CronService) computeNextRun(schedule, nowMS)`
- `(cs *CronService) recomputeNextRuns()`
- `(cs *CronService) getNextWakeMS()`
- `(cs *CronService) Load()` / `SetOnJob(handler)`
- `(cs *CronService) loadStore()` / `saveStoreUnsafe()`
- `(cs *CronService) AddJob(...)`
- `(cs *CronService) UpdateJob(job)`
- `(cs *CronService) RemoveJob(jobID)` / `removeJobUnsafe(jobID)`
- `(cs *CronService) EnableJob(jobID, enabled)`
- `(cs *CronService) ListJobs(includeDisabled)`
- `(cs *CronService) Status()`
- `generateID()`

## 詳細動作
### 1. 初期化と起動
- `NewCronService` は `storePath`, `onJob`, `gronx.New()` を設定し、生成時点で `loadStore()` を試みる。
- `Start` は以下を行う。
  1. 多重起動なら何もしない。
  2. ストアを再ロードする。
  3. `recomputeNextRuns()` で全有効ジョブの次回実行時刻を再計算する。
  4. 保存後、`stopChan` と `rescheduleCh` を作って `runLoop` を goroutine 起動する。

### 2. 待機ループ
`runLoop` は毎回 `getNextWakeMS()` を参照し、最短ジョブの時刻まで `time.NewTimer` で待機する。
- `stopChan` 受信で終了。
- `rescheduleCh` 受信でタイマーを捨てて再計算。
- タイマー発火で `checkJobs()` を呼ぶ。

### 3. 期日到来ジョブの抽出
`checkJobs` はロック下で以下を実施する。
1. サービス停止済みなら即 return。
2. `NextRunAtMS <= now` の有効ジョブ ID を収集する。
3. 重複実行防止のため、対象ジョブの `State.NextRunAtMS` を先に `nil` にする。
4. 中間状態を保存してロック解除。
5. 各 `jobID` を `executeJobByID` でロック外実行する。

### 4. 個別ジョブ実行
`executeJobByID` はまず読み取りロックで対象ジョブをコピーし、ロック外で `onJob` を呼ぶ。完了後に再度ロックを取得し、最新ストア上のジョブへ結果を書き戻す。
- `LastRunAtMS` は実行開始時刻。
- `LastStatus` は `ok` または `error`。
- `LastError` は失敗時のみ設定。
- `schedule.Kind == "at"` の場合:
  - `DeleteAfterRun == true` なら削除。
  - そうでなければ `Enabled=false` かつ `NextRunAtMS=nil`。
- それ以外は `computeNextRun` で次回時刻を再設定する。
- 保存後に `notifyReschedule()` を送る。

### 5. 次回実行時刻計算
`computeNextRun` は `Kind` ごとに分岐する。
- `at`
  - `AtMS` が `nowMS` より未来ならその値を返す。
  - 過去または未設定なら `nil`。
- `every`
  - `EveryMS > 0` のとき `nowMS + EveryMS` を返す。
  - 0 以下または未設定は `nil`。
- `cron`
  - `Expr` が空なら `nil`。
  - `gronx.NextTickAfter(schedule.Expr, now, false)` で次回時刻を求める。
  - 計算失敗時はログ出力して `nil`。

`CronSchedule.TZ` フィールドは保持されるが、このファイル内では次回計算に使用していない。

### 6. ストア操作 API
- `AddJob`
  - 新規 ID を生成し、`Payload.Kind` を固定で `agent_turn` に設定する。
  - `schedule.Kind == "at"` のジョブは `DeleteAfterRun=true`。
- `UpdateJob`
  - 同一 ID のジョブを丸ごと置き換える。
- `RemoveJob`
  - 指定 ID を除去し、保存と再スケジュール通知を行う。
- `EnableJob`
  - 有効化時は次回実行時刻を再計算、無効化時は `NextRunAtMS=nil`。
- `ListJobs`
  - `includeDisabled` が偽なら有効ジョブのみ返す。
- `Status`
  - `enabled`, `jobs`, `nextWakeAtMS` を返す。

## 入出力・副作用・永続化
### 入力
- `storePath string`
- ジョブ定義 (`CronSchedule`, `message`, `deliver`, `channel`, `to`)
- `onJob JobHandler`

### 出力
- API に応じて `*CronJob`, `[]CronJob`, `map[string]interface{}`, `error`, `bool`

### 副作用
- バックグラウンド goroutine を起動・停止する。
- `onJob` コールバックを非同期タイミングで呼び出す。
- `log.Printf` により実行エラーや保存失敗を標準ログへ出力する。

### 永続化
- ストアファイルを JSON で保存する。
- 保存先ディレクトリは `os.MkdirAll(dir, 0755)` で作成する。
- ファイルは `json.MarshalIndent` した内容を `0600` 権限で `os.WriteFile` する。

## 依存関係
- `github.com/adhocore/gronx`
  - cron 式から次回実行時刻を計算する。
- `sync.RWMutex`
  - ストアと実行状態の排他制御。
- `crypto/rand`, `encoding/hex`
  - ジョブ ID 生成。
- `encoding/json`, `os`, `filepath`
  - JSON ストアの読み書き。
- `time`
  - タイマーループ・ミリ秒時刻計算。
- `log`
  - 実行時エラーログ出力。

## エラーハンドリング・制約
- `Start`, `AddJob`, `UpdateJob` は保存/読込失敗を `error` として返す。
- 一方で `checkJobs`, `executeJobByID`, `removeJobUnsafe`, `EnableJob` 中の保存失敗はログ出力のみで継続する。
- `UpdateJob` で対象 ID が見つからない場合は `job not found` を返す。
- `RemoveJob` は削除成否を `bool` で返し、存在しない ID は `false`。
- `generateID` は `crypto/rand` 失敗時に `time.Now().UnixNano()` 文字列へフォールバックする。
- `Status` 内で `enabledCount` を数えているが返り値には含めていない。
