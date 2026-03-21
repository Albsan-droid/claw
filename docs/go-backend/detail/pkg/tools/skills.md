# pkg/tools/skills.go 詳細設計

## 対象ソース
- `pkg/tools/skills.go`

## 概要
外部スキル定義群を LLM ツールとして参照できるようにするラッパーである。スキル一覧取得と単一スキル本文取得の 2 つの action を提供し、実体の探索・読み込みは `pkg/skills.SkillsLoader` に委譲する。

## 責務
- スキル一覧をツール呼び出しで取得できるようにする。
- 指定名のスキル本文を読み込む。
- `SkillsLoader` の戻り値を LLM 向け文字列へ整形する。

## 主要な型・関数・メソッド
### `type SkillTool struct`
- フィールド: `loader *skills.SkillsLoader`
- `NewSkillTool(loader *skills.SkillsLoader) *SkillTool`
- `Execute(ctx, args) *ToolResult`

## 詳細動作
- `action` は `skill_list` と `skill_read` のみ受け付ける。
- `skill_list` では `loader.ListSkills()` を呼び、各スキルを `- name (source): description` 形式で列挙する。
- `skill_read` では `name` を必須とし、`loader.LoadSkill(name)` の成否で存在判定する。
- 結果は常に `SilentResult` で返し、ユーザーへ直接送る前提ではなくエージェント内部コンテキスト向けとなっている。

## 入出力・副作用・永続化
- 入力: `action`, `name`, `SkillsLoader` 実装。
- 出力: スキル一覧文字列、スキル本文、またはエラー結果。
- 副作用: スキルファイルの読み込み（`SkillsLoader` 経由）。
- 永続化: なし。

## 依存関係
- 標準ライブラリ: `context`, `fmt`, `strings`
- 他パッケージ: `github.com/KarakuriAgent/clawdroid/pkg/skills`
- 同一パッケージ: `SilentResult`, `ErrorResult`

## エラーハンドリング・制約
- `name` 未指定の `skill_read` はエラー。
- ローダーが 0 件を返した場合は `No skills available` を返す。
- 本ツール自体はローダー未設定時の防御コードを持たないため、呼び出し側で注入保証が必要である。
