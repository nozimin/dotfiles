# /review-report

コードの変更をレビュー skill でレビューし、結果をマージ判定と 4 つのグループに整理して出す。レビュー自体はレビュー skill（既定は Claude Code の `/code-review`、Codex の `codex review`）に任せ、この skill は結果の整理と出力を受け持つ。

dotfiles の plugin `nozimin` の skill として `lib/agents/nozimin/skills/review-report/` に置き、`cmd/install_skills` で Claude Code と Codex に入れる（仕組みは [lib/skills.md](skills.md)）。

## 使い方

```
Claude Code: /nozimin:review-report [/レビューskill ...] <レビュー対象>
Codex CLI:  $nozimin:review-report [$レビューskill ...] <レビュー対象>
```

例:

```
/nozimin:review-report #123
/nozimin:review-report https://github.com/<owner>/<repo>/pull/123
/nozimin:review-report main ブランチとの差分
/nozimin:review-report /original-review /code-review この PR
$nozimin:review-report 未コミットの変更
```

- 手動実行専用（Claude Code は `disable-model-invocation: true`、Codex は `agents/openai.yaml` の `allow_implicit_invocation: false`）。
- レビュー対象を書かないと「何をレビューしたら良いか教えてください。」とだけ出して終わる。直前に `/code-review` などを実行していれば、その対象と結果を引き継ぐ（レビューをやり直さない）。
- `/`（Codex では `$`）で始まる語はレビュー skill として扱う。指定すればその skill だけを順に使い、既定のレビューは呼ばない。複数の結果は、同じ問題を 1 項目にまとめ、項目ごとに指摘元を書く。
- レビュー skill が見つからない、または失敗したときは、そこで止まる。一部の結果だけで判定はしない。
- 読み取り専用。コードの変更、コミット、checkout はしない。

## 出力

| 判定 | 条件 |
|---|---|
| ✅マージOK | 🔴 も 🟡 も無い。🟡 があっても、どれもマージを止める理由にならないと AI が判断すれば ✅（理由を書く） |
| ⚠️要確認 | 🔴 が無く、🟡 がある |
| 🚫重大な問題あり | 🔴 が 1 件以上 |

| グループ | 中身 |
|---|---|
| 🔴修正必要 | 既存システムが動かなくなる可能性、パフォーマンスの極端な悪化 |
| 🟡要確認事項 | 技術負債・将来の不具合の可能性、デグレの懸念、エッジケースなど。誤検知と思われる指摘も、理由を付けてここに残す |
| 🟢良いプラクティス | 実装で考慮されていて良い点 |
| 👀提案(スコープ外) | 変更の目的から外れる、既存の不具合、重複した実装、機能追加の案など |

- 🔴 → 🟡 → 🟢 は通し番号で、👀 は番号なしの箇条書き。0 件のグループは省く。
- チャットには見出しと箇条書きで全文を出す。

## PR への投稿

レビュー対象が PR（番号、URL、「この PR」）のときだけ、まとめコメントを 1 件投稿する。ブランチ名で指定したときは、そのブランチに PR があっても投稿しない。

- 投稿前に下書きをチャットに見せ、承認されたときだけ `gh pr comment` で投稿する。Claude Code の許可確認も毎回出る。
- グループごとに `<details>` で折りたたみ、見出しに件数を出す。🔴 だけは開いた状態にする。
- 行ごとのコメントは付けない。再実行すると、前のコメントは残したまま新しいコメントを投稿する。
- `/code-review` の `--comment` は付けずに実行する（行ごとのコメントが二重になるため）。

## Codex で使うとき

- 既定のレビューは `codex review`。PR やブランチを対象にするときは、そのブランチを checkout してから実行する（skill は checkout しない）。コミットの範囲は `<base>..HEAD` の形だけ扱える。
- サンドボックスがネットワークを許可していないと `codex review` が失敗する。ネットワークを許可して実行する。
