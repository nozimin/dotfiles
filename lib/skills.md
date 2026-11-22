# Agent Skills

## 仕組み

dotfiles の skills は 1 つの Claude Code 形式 plugin `nozimin` にまとめ、Claude Code と Codex の両方にインストールする。marketplace 名は `dotfiles`、plugin ID は `nozimin@dotfiles`。

- Claude Code はローカル marketplace の plugin をその場所から直接読む。`lib/agents/` を編集した後は、Claude Code で `/reload-plugins` を実行すると反映される。
- Codex CLI は marketplace を `~/.codex/plugins/cache/dotfiles/nozimin/local/` にコピーする。`lib/agents/nozimin/` に変更があれば、`cmd/install_skills` がコピーを入れ直す。
- 両方ともユーザー全体にインストールするため、どのディレクトリからでも使える。
- `cmd/install_skills` は何度実行してもよい。登録済みの手順は `ok` を出して飛ばす。marketplace が以前の clone の場所を指している場合は、現在の clone に登録し直すか確認する。
- `cmd/setup` は plugin が有効でない場合に確認し、許可されたときだけ `cmd/install_skills` を実行する。

インストール時に clone の絶対パスを `~/.config/dotfiles/repo` に保存する。skill と同梱スクリプトはこの場所から dotfiles を見つけるため、Codex のキャッシュから起動しても動作する。

## 呼び出し

CLI ごとに明示呼び出しの記法が異なる。

- Claude Code: `/nozimin:sync-to-dotfiles`
- Codex CLI: `$nozimin:sync-to-dotfiles`（CLI の `/skills` で一覧を確認し、`$` で skill を選ぶ）

Codex では `agents/openai.yaml` の `policy.allow_implicit_invocation: false` を使い、明示的に選んだときだけ skill を実行する。`SKILL.md` の `disable-model-invocation: true` は Claude Code の同じ動作のために残す。

## skill の追加

`lib/agents/nozimin/skills/<名前>/SKILL.md` を追加する。明示呼び出しだけにする skill には、Codex 用に `agents/openai.yaml` も置く。

```yaml
policy:
  allow_implicit_invocation: false
```

Claude Code は `/reload-plugins` で反映し、Codex は `cmd/install_skills` を再実行してキャッシュを更新する。

スキルにスクリプトや参照ファイルを同梱するときは、`SKILL.md` があるディレクトリからの相対パスで記述する（例: `scripts/collect`）。Claude Code の `${CLAUDE_SKILL_DIR}` のような製品固有変数は使わない。実行時は agent の skill 一覧に表示された `SKILL.md` の場所を基準に解決する。
