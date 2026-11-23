# 同梱スキルの出典

以下のファイルは、[mattpocock/skills](https://github.com/mattpocock/skills) のコミット [abeeaf95660ba9e8b7c753eb38f441ca707a8823](https://github.com/mattpocock/skills/commit/abeeaf95660ba9e8b7c753eb38f441ca707a8823) から同梱しています。

- `grilling/SKILL.md`: [上流の原文](https://github.com/mattpocock/skills/blob/abeeaf95660ba9e8b7c753eb38f441ca707a8823/skills/productivity/grilling/SKILL.md)
- `grill-with-docs/SKILL.md`: [上流の原文](https://github.com/mattpocock/skills/blob/abeeaf95660ba9e8b7c753eb38f441ca707a8823/skills/engineering/grill-with-docs/SKILL.md)
- `domain-modeling/SKILL.md` と2つの書式リファレンス: `grill-with-docs` が必要とする依存ファイル。

同梱した `grill-with-docs/SKILL.md` では、上流の手順1行をローカルの実行環境と作業手順に置き換えています。Claude Code では `nozimin:` 名前空間付きのスキル名を使い、Codex では同階層のスキルファイルを読み込みます。インタビュー前に両方のスキルを読み、各ラウンドの後に `domain-modeling` を使って確定した用語と対象となる判断を記録します。`agents/openai.yaml` は Codex で明示的な呼び出しを必須にする dotfiles のパッケージ設定で、上流のファイルではありません。

著作権 © 2026 Matt Pocock。MIT ライセンスに基づきます。詳しくは [LICENSE.mattpocock](LICENSE.mattpocock) を参照してください。

## 同梱ファイルの更新

上流スキルを更新するときは、`docs/skills/` の管理元を編集し、対応する変更を `lib/agents/nozimin/skills/` にも手動で反映します。上流の内容を変更した場合は、上記の固定コミットとローカル変更の説明も更新してください。MIT ライセンス表示を変更する場合は、管理元と配布コピーの両方を更新します。

`cmd/install_skills` は管理元と配布コピーの差分を対象パス付きで警告しますが、配布コピーの複製、上書き、削除は行いません。警告の内容を確認し、変更を確定したら両方のツリーをコミットしてください。
