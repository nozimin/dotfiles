---
name: grill-with-docs
description: A relentless interview to sharpen a plan or design, which also creates docs (ADR's and glossary) as we go.
disable-model-invocation: true
---

インタビューを始める前に、現在の会話で両方のスキルを読み込む。Claude Code では Skill ツールで「nozimin:grilling」と「nozimin:domain-modeling」を呼び出す。Codex では同階層の `../grilling/SKILL.md` と `../domain-modeling/SKILL.md` を読み、その指示に従う。

同じ会話の間、両方のスキルを有効に保つ。`grilling` を使って設計の分岐を整理し、各ラウンドで現時点で答えられる質問を尋ねる。ユーザーの回答ごとに `domain-modeling` を適用し、その場で確定した用語や判断を扱う。用語の食い違いを指摘し、関係するファイルやコードを確認し、用語が確定した時点で `GLOSSARY.md` を更新する。判断を後から変えるコストが高く、背景なしでは意外で、実際のトレードオフから選ばれた場合に限り、その場で ADR を提案する。ユーザーが承諾したら記録する。更新した文脈を踏まえて grilling のラウンドを続ける。対話中の文書更新もこのスキルの作業に含む。ユーザーが別途依頼しない限り、設計の実装には進まない。
