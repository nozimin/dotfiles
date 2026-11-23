---
name: grill-with-docs
description: A relentless interview to sharpen a plan or design, which also creates docs (ADR's and glossary) as we go.
disable-model-invocation: true
---

In Claude Code, call the Skill tool twice, for "nozimin:grilling" and "nozimin:domain-modeling". In Codex, read and follow the sibling files `../grilling/SKILL.md` and `../domain-modeling/SKILL.md` in this same conversation.

First follow `grilling` to reach shared understanding; then follow `domain-modeling` to update the glossary and ADRs as decisions crystallise. Keep both skills in the current conversation so they can use the plan and decisions already discussed. Preserve the current conversation context throughout both workflows.
