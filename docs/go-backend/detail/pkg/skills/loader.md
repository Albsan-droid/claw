# pkg/skills/loader.go 詳細設計

## 対象ソース
- `pkg/skills/loader.go`

## 概要
`{dataDir}/skills`・グローバル・ビルトインの 3 系統に存在する `SKILL.md` を探索し、スキル一覧構築・単体読み込み・コンテキスト向け連結・XML サマリ生成を行うローダーである。前置メタデータは JSON 互換または簡易 YAML として解析する。

## 責務
- スキル格納ディレクトリ群を優先順位付きで探索する。
- `SKILL.md` の frontmatter から名前と説明を抽出する。
- 名前・説明の妥当性を検証し、不正スキルを除外する。
- スキル本文の読み込み、frontmatter 除去、コンテキスト連結を行う。
- system prompt 用 XML サマリを生成する。

## 主要な型・関数・メソッド
### 定数・正規表現
- `namePattern = ^[a-zA-Z0-9]+(-[a-zA-Z0-9]+)*$`
- `MaxNameLength = 64`
- `MaxDescriptionLength = 1024`

### 型
- `SkillMetadata { Name, Description }`
- `SkillInfo { Name, Path, Source, Description }`
- `func (info SkillInfo) validate() error`
- `type SkillsLoader struct { dataDir, dataSkills, globalSkills, builtinSkills string }`

### 主なメソッド
- `NewSkillsLoader(dataDir, globalSkills, builtinSkills string) *SkillsLoader`
- `ListSkills() []SkillInfo`
- `LoadSkill(name string) (string, bool)`
- `LoadSkillsForContext(skillNames []string) string`
- `BuildSkillsSummary() string`
- `getSkillMetadata(skillPath string) *SkillMetadata`
- `parseSimpleYAML(content string) map[string]string`
- `extractFrontmatter(content string) string`
- `stripFrontmatter(content string) string`
- `escapeXML(s string) string`

## 詳細動作
- `dataSkills` は `filepath.Join(dataDir, "skills")` で組み立てられる。
- `ListSkills` は `{dataDir}/skills -> global -> builtin` の順にディレクトリを走査し、同名スキルの下位ソースをスキップする。
- スキルの存在条件は `<dir>/<skill>/SKILL.md` が存在することである。
- frontmatter が無い場合、`getSkillMetadata` はディレクトリ名を `Name` に採用する。
- frontmatter は JSON を先に試し、失敗したら `parseSimpleYAML` へフォールバックする。
- `validate` は空値、最大長超過、名前パターン不一致を `errors.Join` で束ねる。
- 不正スキルは `slog.Warn` を出して一覧から除外する。
- `LoadSkillsForContext` は複数スキルを `### Skill: <name>` 見出し付きで連結し、区切りに `---` を使う。
- `BuildSkillsSummary` は `<skills><skill>...</skill></skills>` の XML 風文字列を返す。

## 入出力・副作用・永続化
- 入力: データディレクトリ群、スキル名一覧、`SKILL.md` ファイル内容。
- 出力: `SkillInfo` 一覧、スキル本文、連結文字列、XML サマリ。
- 副作用: ファイルシステム走査と読み取り、`slog.Warn` 出力。
- 永続化: なし。

## 依存関係
- 標準ライブラリ: `encoding/json`, `errors`, `fmt`, `log/slog`, `os`, `path/filepath`, `regexp`, `strings`
- 利用側: `pkg/tools/skills.go` など

## エラーハンドリング・制約
- ディレクトリ読み取り失敗やファイル欠如は黙ってスキップする設計である。
- YAML 解析は簡易 `key: value` のみ対応し、ネストや複雑な YAML は扱えない。
- XML サマリでは `&`, `<`, `>` のみエスケープする。
