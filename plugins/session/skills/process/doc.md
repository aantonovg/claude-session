# Process: a document

A plan, a specification, a design note, a report, a page of rules. The result sits on ladder level
e: no run can judge it, so it gets a stronger author, a checklist read from the level above and,
when it is a key document, the evidence chain one class step above its author. Read `core.md` and
`SKILL.md` first.

## Stages and gates

| stage | task file | gate | lite | std | full |
|---|---|---|---|---|---|
| `intent` — who reads this document, what they must be able to do after it | `intent.md` | the user confirms the purpose, the reader and the criteria | written by the main session, no gate | user gate | user gate |
| `subtasks` — the sections the purpose needs | `subtasks.md` | every part of the purpose has a section, no section outside it | folded into `intent.md` | yes | yes |
| `specification` — what the document must state, and its constraints of form and length | `specification.md` | traceability to the sections, every constraint measurable | folded into `intent.md` | yes | yes |
| `scenarios` — the questions a reader must be able to answer from the text | `scenarios.md` | every requirement has a question; the hard cases are among them | one-liners | yes | yes, with the questions a bad draft would fail |
| `verification-plan` — how each question is checked | `verification-plan.md` | every question has a row: `existing`, `missing` or `no possible` oracle | folded into `intent.md` | yes | yes |
| `checks` — the reader checklist, and any runnable check of form (links, counts, structure) | `tests.md` | every question is a line of the checklist; a runnable check exists where form allows | – | yes | yes, plus one question a draft must fail before the fix |
| `result` — the document, written one class step up, section by section | `changes`, `runs` | the checklist is answered from the text alone, with no section missing or cut mid-sentence | yes | yes | yes |
| `review` — the evidence chain over the approved aspects | `reviews` | every hint is confirmed or refuted by a quote of the text or a source; undetermined goes to the user | 1 merged critic | 2-3 aspects | 3-5 aspects |
| `coverage` — questions without a checklist line, sections without a question | `coverage.md` | both lists written out, empty ones said so | – | yes | yes |
| `closure` — what the document decides and what it leaves open | `report.md` | open points, hit ceilings and unverified claims named | short in chat | yes | yes |

## What this process insists on

- The author writes the skeleton first and then one section per edit, never a whole document in
  one answer. A section that came back cut off is finished by a scoped repair, not rewritten.
- A key document — a plan, a decision contract, a specification, a closure report — never reaches
  the user unchecked: the chain runs one class step above its author before the user sees it.
- A document written by a carrier that carried the whole conversation is biased by it and always
  goes to a clean-context check, whatever the level says.
- Every claim of the document carries its source. A claim the author could not source is written
  as an open question in the text, never smoothed over.
- Decisions the document rests on go to the user while the draft is still cheap to change, not at
  the end.
- One round of review, one round of fixes. A second round needs the user's word.
