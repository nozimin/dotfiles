# Vendored skills attribution

These files are vendored from [mattpocock/skills](https://github.com/mattpocock/skills) at commit [abeeaf95660ba9e8b7c753eb38f441ca707a8823](https://github.com/mattpocock/skills/commit/abeeaf95660ba9e8b7c753eb38f441ca707a8823).

- `grilling/SKILL.md`: [upstream source](https://github.com/mattpocock/skills/blob/abeeaf95660ba9e8b7c753eb38f441ca707a8823/skills/productivity/grilling/SKILL.md)
- `grill-with-docs/SKILL.md`: [upstream source](https://github.com/mattpocock/skills/blob/abeeaf95660ba9e8b7c753eb38f441ca707a8823/skills/engineering/grill-with-docs/SKILL.md)
- `domain-modeling/SKILL.md` and its two format references: dependency required by `grill-with-docs`.

The vendored `grill-with-docs/SKILL.md` adds local runtime and workflow instructions after the upstream text: Claude Code uses namespaced `nozimin:` skill names, while Codex reads the sibling skill files. Both skills are loaded before the interview and domain-modeling records resolved terms and eligible decisions inline after each round. Its `agents/openai.yaml` is dotfiles packaging metadata that enforces explicit invocation in Codex; it is not an upstream file.

Copyright (c) 2026 Matt Pocock. Licensed under the MIT License; see [LICENSE.mattpocock](LICENSE.mattpocock).
