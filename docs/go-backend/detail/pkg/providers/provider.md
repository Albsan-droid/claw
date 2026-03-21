# pkg/providers/provider.go

## 対象ソース
- `pkg/providers/provider.go`

## 概要
LLM プロバイダ生成の単一入口を提供する薄いファクトリ関数。現在は `AnyLLMAdapter` への委譲のみを行う。

## 責務
- `config.Config` から LLM 接続設定を取り出す
- `LLMProvider` 実装の生成を 1 箇所に集約する

## 主要な型・関数・メソッド
- `CreateProvider(cfg *config.Config) (LLMProvider, error)`

## 詳細動作
- `cfg.LLM.Model`, `cfg.LLM.APIKey`, `cfg.LLM.BaseURL` をそのまま `NewAnyLLMAdapter` に渡す。
- ほかの分岐や provider 種別判定はこのファイルには無い。
- コメント上も「LLM ライブラリ差し替え時はここだけ変更する」意図が明示されている。

## 入出力・副作用・永続化
### 入力
- `*config.Config`

### 出力
- `LLMProvider`
- 生成失敗時 `error`

### 副作用
- 直接的にはなし（委譲先の初期化処理に依存）

### 永続化
- なし

## 依存関係
- `pkg/config`
- 同一パッケージの `NewAnyLLMAdapter`, `LLMProvider`

## エラーハンドリング・制約
- エラー処理はすべて `NewAnyLLMAdapter` に委譲され、そのまま返す。
- 現状は `AnyLLMAdapter` 以外の実装へ切り替えるロジックを持たない。
