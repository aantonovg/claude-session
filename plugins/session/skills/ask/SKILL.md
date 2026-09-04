---
name: ask
description: Ask the user without blocking the session. Use when a question has timed out unanswered (askUserQuestionTimeout), when several decisions have piled up, or when the user is likely away. Writes a short Russian context document with the options and the chosen defaults, opens it in Plannotator in the background, continues on reversible defaults, and acts on the annotations when they arrive.
---

# Ask without blocking

A pending AskUserQuestion, permission prompt or plan approval blocks the turn; while
it waits the keep-warm pings do not fire and after an hour the cache is gone. This
skill turns a question into an asynchronous review: the session keeps working, the
user answers when present, the answer arrives as a normal turn.

## When

- An AskUserQuestion auto-continued without an answer (`askUserQuestionTimeout`).
- Two or more decisions are waiting and the user has not answered for a while.
- The user said they are away, or the session runs unattended.

Do not use it for a single quick question while the user is clearly present: a plain
AskUserQuestion with the recommended option first is faster.

## Steps

1. **Classify each decision**: *reversible* (local edits, private branches, drafts,
   anything undone with one command and seen by nobody else) or *not reversible*
   (published text, review requests, releases, Jira transitions, messages to people,
   deletions). Reversible ones proceed on the recommended option; the rest wait.
2. **Write the document** `~/.claude/projects/<encoded-cwd>/questions/<YYYY-MM-DD-HHMM>-<slug>.md`
   (`<encoded-cwd>` = cwd with `/` → `-`; `mkdir -p`). In Russian, plain words, one
   section per decision:

   ```
   # Вопросы: <тема>, <дата>

   ## 1. <вопрос в одну строку>
   Контекст: 2-4 строки, что известно и почему это важно.
   Варианты: A) … (рекомендую, потому что …) B) … C) …
   Обратимо: да, продолжаю по варианту A / нет, жду ответа.

   ## 2. …
   ```

3. **Open it in the background**: Bash `plannotator annotate <file>` with
   `run_in_background: true` (never synchronously: a synchronous call blocks the turn
   the same way a dialog does). Tell the user in one line where the document is and
   that the browser tab is open.
4. **Continue** the reversible work on the defaults; for the blocked items say what is
   paused and end the turn normally so the pings keep the cache alive.
5. **When the background command finishes** (the user submitted or closed the tab),
   read its output file: it holds the feedback per section ("# File Feedback" with
   quotes). Apply each answer: keep or redo the reversible choices, unblock or drop
   the paused items. If the tab was closed without feedback, treat the defaults as
   accepted for reversible items and keep the rest paused; say so.

## Rules

- One document per batch, never one per question.
- Recommended option first and marked; the document says which default is already in
  motion.
- Never re-ask the same question with AskUserQuestion after it went to a document.
- The document stays on disk as the record of the decision.
