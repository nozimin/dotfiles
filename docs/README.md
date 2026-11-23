# ドキュメント

このディレクトリには、機能仕様と上流から同梱したスキルの管理元を置きます。

- [`specs/`](specs/): 機能の目的、要件、受け入れ条件を記録します。例: [sync-to-dotfiles](specs/sync-to-dotfiles.md)、[vuln-check](specs/vuln-check.md)。
- [`guides/`](guides/): 人が読むための解説です。例: [vuln-check の流れ](guides/vuln-check-flow.html)（ブラウザで開く）。
- [`skills/`](skills/): 上流由来の `grilling`、`grill-with-docs`、`domain-modeling` の管理元、出典、ライセンスを記録します。出典と更新手順は [UPSTREAM.md](skills/UPSTREAM.md) を参照してください。
- [`../lib/agents/`](../lib/agents/): Claude Code と Codex に配布する plugin の実体です。管理元との差分は [`../cmd/install_skills`](../cmd/install_skills) がパス付きで警告しますが、配布コピーは更新しません。両方を手動で揃えてから再インストールしてください。

Agent Skills の導入と更新手順は [`../lib/skills.md`](../lib/skills.md) にあります。
