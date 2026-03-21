# pkg/agent/memory.go

## 対象ソース
- `pkg/agent/memory.go`

## 概要
`MemoryStore` は、エージェント用の長期メモリ (`MEMORY.md`) と日次ノート (`YYYYMM/YYYYMMDD.md`) をファイルベースで管理する。プロンプト注入用の整形済みテキストもここで作る。

## 責務
- メモリ用ディレクトリの作成
- 長期メモリの読み書き
- 当日ノートの読み取り・追記
- 直近 N 日分の日次ノート収集
- LLM へ渡すメモリコンテキストの組み立て

## 主要な型・関数・メソッド
### 型
- `MemoryStore`
  - `dataDir`: ベースデータディレクトリ
  - `memoryDir`: `dataDir/memory`
  - `memoryFile`: `dataDir/memory/MEMORY.md`

### メソッド
- `NewMemoryStore(dataDir string) *MemoryStore`
- `getTodayFile() string`
- `ReadLongTerm() string`
- `WriteLongTerm(content string) error`
- `ReadToday() string`
- `AppendToday(content string) error`
- `GetRecentDailyNotes(days int) string`
- `GetMemoryContext() string`

## 詳細動作
### 初期化
- `NewMemoryStore` は `dataDir/memory` を `0755` で `os.MkdirAll` し、`MEMORY.md` の絶対位置を保持する。

### 長期メモリ
- `ReadLongTerm` は `memoryFile` を `os.ReadFile` し、成功時のみ文字列を返す。失敗時は空文字列。
- `WriteLongTerm` は `os.WriteFile(..., 0644)` で上書き保存する。

### 日次ノート
- `getTodayFile` は `time.Now()` を `20060102` 形式にし、`YYYYMM/YYYYMMDD.md` へ変換する。
- `ReadToday` は当日ファイルを読めなければ空文字列を返す。
- `AppendToday`
  - 月ディレクトリを `os.MkdirAll(..., 0755)` で作る
  - 既存ファイルが空なら `# YYYY-MM-DD` 見出しを付けて新規作成
  - 既存内容があるなら末尾へ `"\n" + content` を足す
  - 保存は `0644`

### 直近ノート収集
- `GetRecentDailyNotes(days)` は当日から過去方向へ `days` 回ループし、存在するファイルだけ収集する。
- 収集結果は `"\n\n---\n\n"` で連結し、1 件もなければ空文字列を返す。

### プロンプト用整形
- `GetMemoryContext` は次の順でセクションを組み立てる。
  - 長期メモリがあれば `## Long-term Memory`
  - 直近 3 日分ノートがあれば `## Recent Daily Notes`
- どちらか 1 つでも存在すれば、全体を `# Memory` で包んで返す。
- 何も無い場合は空文字列を返す。

## 入出力・副作用・永続化
### 入力
- `content string`
- `days int`
- `dataDir`

### 出力
- 長期メモリ文字列、当日メモ文字列、整形済みコンテキスト文字列
- 書き込み系は `error`

### 副作用
- ディレクトリ作成 (`os.MkdirAll`)
- ファイル読み書き (`os.ReadFile`, `os.WriteFile`)

### 永続化
- `dataDir/memory/MEMORY.md`
- `dataDir/memory/YYYYMM/YYYYMMDD.md`

## 依存関係
- 標準ライブラリ: `fmt`, `os`, `path/filepath`, `time`

## エラーハンドリング・制約
- 読み込み失敗は原則空文字列にフォールバックし、呼び出し元へエラーを返さない。
- `NewMemoryStore` と `AppendToday` の `MkdirAll` エラーは無視される。
- 追記サイズや保持期間の制限はこの実装には無い。
