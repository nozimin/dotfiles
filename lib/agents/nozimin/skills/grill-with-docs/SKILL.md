---
name: grill-with-docs
description: A relentless interview to sharpen a plan or design, which also creates docs (ADR's and glossary) as we go.
disable-model-invocation: true
---

Before the interview starts, load both skills in the current conversation. In Claude Code, call the Skill tool for "nozimin:grilling" and "nozimin:domain-modeling". In Codex, read and follow the sibling files `../grilling/SKILL.md` and `../domain-modeling/SKILL.md`.

Keep both skills active throughout the same conversation. Use `grilling` to map the design tree and ask each round's frontier questions. After each user response, apply `domain-modeling` to the terms and decisions that have just crystallised: challenge conflicting vocabulary, check relevant files or code, and update `GLOSSARY.md` inline as soon as a term is resolved. Offer an ADR at that point only when the decision is hard to reverse, surprising without context, and the result of a real trade-off; if the user accepts, record it then. Continue the grilling rounds with this updated context. These inline documentation updates are part of this skill; do not implement the design unless the user separately asks for implementation.
