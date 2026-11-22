# Agent Skills

## 仕組み

dotfiles の skills は 1 つの Claude Code 形式 plugin `nozimin` にまとめ、Claude Code と Codex の両方にインストールする。marketplace 名は `dotfiles`、plugin ID は `nozimin@dotfiles`。

- Claude Code はローカル marketplace の plugin をその場所から直接読む。`lib/agents/` を編集した後は、Claude Code で `/reload-plugins` を実行すると反映される。
- Codex CLI は marketplace を `~/.codex/plugins/cache/dotfiles/nozimin/local/` にコピーする。`lib/agents/nozimin/` に変更があれば、`cmd/install_skills` がコピーを入れ直す。
- 両方ともユーザー全体にインストールするため、どのディレクトリからでも使える。
- `cmd/install_skills` は何度実行してもよい。登録済みの手順は `ok` を出して飛ばす。marketplace が以前の clone の場所を指している場合は、現在の clone に登録し直すか確認する。
- clone の場所を切り替える場合は、Claude Code と Codex の marketplace 変更を始める前に一度確認する。断ると両 CLI の設定と `~/.config/dotfiles/repo` はそのまま。切り替え中にエラーが起きたときは repo pointer を更新せず、`~/.config/dotfiles/repo.migrating` を残す。この marker がある間は `collect` が停止し、違う clone を誤操作しない。エラーを直した後に移行先 clone から `cmd/install_skills` を再実行して移行を完了する。 Codex が最後に登録した marketplace path は `~/.config/dotfiles/codex-marketplace` に記録する。移行中にさらに clone を移動したり、Claude の更新で中断した場合も、Codex の登録先を検出して再試行できる。
- `cmd/install_skills` と `scripts/with-repo-lock` は `cmd/skills_lock.sh` の `mkdir` lock を共有し、preflight から pointer/marker の更新、または承認された書き込みまでを同時実行から守る。`with-repo-lock` は最初に記録した repo path と pointer を照合し、移行中 marker があれば書き込みを行わない。通常終了では lock を自動で外す。プロセスが強制終了した場合は owner PID が残るので、終了済みと確認してからエラーに表示された `rm -rf ~/.config/dotfiles/install_skills.lock` を実行し、再試行する。owner 情報がない・壊れている、または別 host の lock の場合は自動削除しない。
- `cmd/setup` は plugin が有効でない場合に確認し、許可されたときだけ `cmd/install_skills` を実行する。clone 移動または未完了 migration marker を検出したときは skills を失敗扱いにせず skip として案内し、移動先の `cmd/install_skills` を実行する。 Agent Skill から Terminal.app で setup を続けるときは `cmd/setup --expect-repo <確認済みrepo path>` を使う。この checked mode は lock 内で pointer と移行 marker を確認し、setup 中に `install_skills` が呼ばれる場合は child installer が親の lock を確認して借りる。

インストール時に clone の絶対パスを `~/.config/dotfiles/repo` に保存する。skill と同梱スクリプトはこの場所から dotfiles を見つけるため、Codex のキャッシュから起動しても動作する。

## 既存環境からの移行

以前の clone に未追跡の `.agents/skills/sync-to-dotfiles/` がある場合、Git の merge では削除されない。新しい plugin をインストールして動作を確認した後、旧ディレクトリにローカルの変更がないか調べる。

```sh
git status --short -- .agents/skills/sync-to-dotfiles
diff -ru .agents/skills/sync-to-dotfiles lib/agents/nozimin/skills/sync-to-dotfiles
```

必要なローカル変更は先に保存する。古いコピーだと確認できたら、Codex が再発見しないよう `.agents/skills/` の外へ移動するか、不要なら削除する。`cmd/install_skills` は未追跡ファイルを自動では消さない。

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
