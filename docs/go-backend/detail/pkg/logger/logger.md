# pkg/logger/logger.go 詳細設計

## 対象ソース
- `pkg/logger/logger.go`

## 概要
`logger.go` は Go バックエンド共通の簡易ロガーを提供する。ログレベル判定、標準ライブラリ `log.Println` への整形出力、コンポーネント名/追加フィールド付与、fatal 時のプロセス終了を担う。

## 責務
- ログレベル管理
- ログエントリ整形
- 呼び出し元情報 (`runtime.Caller`) 取得
- フィールド付きログの文字列化
- Fatal ログ時の即時終了

## 主要な型・関数・メソッド
- `type LogLevel int`
- 定数: `DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL`
- 主要変数
  - `logLevelNames map[LogLevel]string`
  - `currentLevel = INFO`
  - `mu sync.RWMutex`
- `type LogEntry struct`
- `func SetLevel(level LogLevel)`
- `func logMessage(level LogLevel, component string, message string, fields map[string]interface{})`
- `func formatComponent(component string) string`
- `func formatFields(fields map[string]interface{}) string`
- レベル別ラッパ
  - `Debug`, `DebugC`, `DebugF`, `DebugCF`
  - `Info`, `InfoC`, `InfoF`, `InfoCF`
  - `Warn`, `WarnC`, `WarnF`, `WarnCF`
  - `Error`, `ErrorC`, `ErrorF`, `ErrorCF`
  - `Fatal`, `FatalC`, `FatalF`, `FatalCF`

## 詳細動作
### 1. レベル管理
- `SetLevel()` は `mu.Lock()` で `currentLevel` を更新する。
- `logMessage()` は `if level < currentLevel { return }` で早期 return する。
- しきい値比較時に read lock を使っていない点は注意事項であり、実装上は単純参照である。

### 2. `logMessage()`
- `LogEntry` を組み立てる。
  - `Timestamp` は `time.Now().UTC().Format(time.RFC3339)`
  - `Level` は `logLevelNames[level]`
  - `Component`, `Message`, `Fields` を設定
- `runtime.Caller(2)` と `runtime.FuncForPC(pc)` により呼び出し元情報を収集し、`Caller` に `"<file>:<line> (<func>)"` 形式で保存する。
- `Fields` が存在する場合は `formatFields()` を使って ` {k=v, ...}` 形式の追記文字列を作る。
- 実際の出力行は `[timestamp] [LEVEL] <component>: message{fields}` 形式で `log.Println()` に渡す。
- `level == FATAL` の場合は出力後に `os.Exit(1)`。

### 3. 補助関数
- `formatComponent()` は空文字なら空、非空なら先頭スペース付き `" <component>:"` を返す。
- `formatFields()` は map をそのまま range して `key=value` 列を `, ` 連結する。並び順は Go map に依存する。

### 4. レベル別 API
- `*C` 系は component 付き。
- `*F` 系は fields 付き。
- `*CF` 系は component と fields の両方付き。
- すべて最終的に `logMessage()` を呼ぶ薄いラッパ。

## 入出力・副作用・永続化
- 入力
  - メッセージ文字列
  - 任意の component 名
  - 任意の fields map
- 出力
  - 標準ロガーへのテキストログ
- 永続化
  - なし（保存先は標準ロガー設定に依存）
- 副作用
  - Fatal ログ時の `os.Exit(1)`
  - `currentLevel` のグローバル更新

## 依存関係
- 標準ライブラリ: `fmt`, `log`, `os`, `runtime`, `strings`, `sync`, `time`

## エラーハンドリング・制約
- `runtime.Caller(2)` 失敗時は `Caller` を空のままにする。
- `formatFields()` の出力順は不定。
- `LogEntry` は内部組み立てに使われるだけで JSON 出力には使っていない。
- `currentLevel` の参照側にロックがないため、厳密な競合防止より簡潔さを優先した実装になっている。
