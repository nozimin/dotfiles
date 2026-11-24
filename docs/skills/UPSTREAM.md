# 同梱スキルの出典

## mattpocock/skills

以下のファイルは、[mattpocock/skills](https://github.com/mattpocock/skills) のコミット [abeeaf95660ba9e8b7c753eb38f441ca707a8823](https://github.com/mattpocock/skills/commit/abeeaf95660ba9e8b7c753eb38f441ca707a8823) から同梱しています。

- `grilling/SKILL.md`: [上流の原文](https://github.com/mattpocock/skills/blob/abeeaf95660ba9e8b7c753eb38f441ca707a8823/skills/productivity/grilling/SKILL.md)
- `grill-with-docs/SKILL.md`: [上流の原文](https://github.com/mattpocock/skills/blob/abeeaf95660ba9e8b7c753eb38f441ca707a8823/skills/engineering/grill-with-docs/SKILL.md)
- `domain-modeling/SKILL.md` と2つの書式リファレンス: `grill-with-docs` が必要とする依存ファイル。

同梱した `grill-with-docs/SKILL.md` では、上流の手順1行をローカルの実行環境と作業手順に置き換えています。Claude Code では `nozimin:` 名前空間付きのスキル名を使い、Codex では同階層のスキルファイルを読み込みます。インタビュー前に両方のスキルを読み、各ラウンドの後に `domain-modeling` を使って確定した用語と対象となる判断を記録します。`agents/openai.yaml` は Codex で明示的な呼び出しを必須にする dotfiles のパッケージ設定で、上流のファイルではありません。

著作権 © 2026 Matt Pocock。MIT ライセンスに基づきます。詳しくは [LICENSE.mattpocock](LICENSE.mattpocock) を参照してください。

## pstack

`pstack/` は、[cursor/plugins](https://github.com/cursor/plugins) のコミット [7a583913eb1b8d1a0ee76753d1a2cf072e7b54f9](https://github.com/cursor/plugins/commit/7a583913eb1b8d1a0ee76753d1a2cf072e7b54f9) にある [`harness/pstack/claude-code/`](https://github.com/cursor/plugins/tree/7a583913eb1b8d1a0ee76753d1a2cf072e7b54f9/harness/pstack/claude-code) を丸ごと同梱しています（pstack 0.15.46、`pstack@cursor-plugins` として配布されている Claude Code 版）。Cursor 用の原本は同コミットの [`pstack/`](https://github.com/cursor/plugins/tree/7a583913eb1b8d1a0ee76753d1a2cf072e7b54f9/pstack) で、上流のスクリプトが Claude Code 版を生成しています。

上流のファイルは変更していません。dotfiles で加えたのは次のファイルだけです。

- `skills/<名前>/agents/openai.yaml`: `disable-model-invocation: true` を持つ 57 個の skill に、Codex でも明示的な呼び出しを必須にするパッケージ設定として追加しました。上流のファイルではありません。`setup-pstack` は上流でも暗黙の呼び出しを許しているため追加していません。

配布先は `nozimin` とは別の plugin `lib/agents/pstack/`（`pstack@dotfiles`）です。上流の Claude Code アダプタ（`docs/harness/claude-code.md`）が `/pstack:<名前>` と `pstack:poteto-agent` の名前空間を前提にしているため、plugin 名を `pstack` のまま保っています。

著作権 © 2026 Lauren Tan。MIT ライセンスに基づきます。詳しくは [pstack/LICENSE](pstack/LICENSE) を参照してください。

### pstack の更新

1. 上流の `harness/pstack/claude-code/` を新しいコミットで取り出す。
2. `docs/skills/pstack/` と `lib/agents/pstack/` を上流ツリーで置き換え、上記の `agents/openai.yaml` を対象 skill に付け直す。新しく増えた skill も frontmatter の `disable-model-invocation` を確認する。
3. 上記の固定コミットと pstack のバージョンを更新する。

## 同梱ファイルの更新

上流スキルを更新するときは、`docs/skills/` の管理元を編集し、対応する変更を `lib/agents/nozimin/skills/`（pstack は `lib/agents/pstack/`）にも手動で反映します。上流の内容を変更した場合は、上記の固定コミットとローカル変更の説明も更新してください。MIT ライセンス表示を変更する場合は、管理元と配布コピーの両方を更新します。

`cmd/install_skills` は管理元と配布コピーの差分を対象パス付きで警告しますが、配布コピーの複製、上書き、削除は行いません。警告の内容を確認し、変更を確定したら両方のツリーをコミットしてください。
