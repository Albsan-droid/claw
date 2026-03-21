# pkg/tools/web.go 詳細設計

## 対象ソース
- `pkg/tools/web.go`

## 概要
Web 検索と URL 取得を提供するネットワーク系ツール群である。検索は Brave API または DuckDuckGo HTML を使用し、URL 取得は JSON 整形・HTML からの本文抽出・生データ返却を切り替える。

## 責務
- 検索プロバイダー抽象 `SearchProvider` を定義する。
- Brave / DuckDuckGo の 2 種類の検索実装を提供する。
- `web_search` ツールとして検索結果を返す。
- `web_fetch` ツールとして URL 内容を取得・整形する。

## 主要な型・関数・メソッド
### 検索関連
- `type SearchProvider interface { Search(ctx, query, count) }`
- `type BraveSearchProvider struct { apiKey string }`
- `type DuckDuckGoSearchProvider struct{}`
- `func (p *DuckDuckGoSearchProvider) extractResults(html string, count int, query string) (string, error)`
- `func stripTags(content string) string`

### `type WebSearchTool`
- フィールド: `provider`, `maxResults`
- `NewWebSearchTool(opts WebSearchToolOptions) *WebSearchTool`
- `Execute(ctx, args) *ToolResult`

### `type WebFetchTool`
- フィールド: `maxChars`
- `NewWebFetchTool(maxChars int) *WebFetchTool`
- `Execute(ctx, args) *ToolResult`
- `extractText(htmlContent string) string`

## 詳細動作
### 検索
- `NewWebSearchTool` は優先順 `Brave > DuckDuckGo` でプロバイダーを選ぶ。どちらも無効なら `nil` を返す。
- Brave は `X-Subscription-Token` 付き JSON API を叩き、結果を `Results for: ...` 形式へ整形する。
- JSON 解析に失敗した場合、レスポンス本文を標準出力へ `fmt.Printf` で出す実装になっている。
- DuckDuckGo は HTML から正規表現で result link / snippet を抽出する単純実装である。
- `WebSearchTool.Execute` は `count` を 1〜10 の範囲で受け、それ以外は既定値を使う。

### 取得
- `web_fetch` は URL を `http/https` のみ許可し、ドメイン必須とする。
- HTTP クライアントは 60 秒タイムアウト、リダイレクトは最大 5 回。
- `Content-Type` と本文先頭で JSON / HTML / raw を判定する。
- HTML は `<script>`, `<style>`, その他タグを除去し、空白正規化後に返す。
- 返却値は `{url,status,extractor,truncated,length,text}` の JSON 文字列を `ForUser` に格納し、`ForLLM` には要約のみを入れる。

## 入出力・副作用・永続化
- 入力: 検索クエリ、件数、URL、最大文字数、API キー設定。
- 出力: 検索結果文字列、取得結果 JSON、またはエラー結果。
- 副作用: 外部 HTTP 通信、Brave API 利用、標準出力へのデバッグ出力（Brave 解析失敗時）。
- 永続化: なし。

## 依存関係
- 標準ライブラリ: `context`, `encoding/json`, `fmt`, `io`, `net/http`, `net/url`, `regexp`, `strings`, `time`
- 同一パッケージ: `ToolResult`, `ErrorResult`

## エラーハンドリング・制約
- URL 不正、HTTP エラー、本文読み取り失敗、検索失敗はエラー結果として返す。
- DuckDuckGo の抽出は正規表現依存で、HTML 構造変更に弱い。
- `web_fetch` の `ForLLM` は要約のみで本文を含まないため、詳細本文は `ForUser` 側を見る必要がある。
