# Subtasks: slug max length

Repository directory: `/Users/aleksandr.antonov/.claude/jobs/rebuild-0.16/results/base/20260921-084315/project-resume`
All paths below are relative to that directory. Every command runs with that directory as cwd.

## Goal

`slug.js` exports `slug(s)`, which lowercases `String(s)` and replaces every run of characters outside `a-z0-9` with one `-`; today `slug('hi!')` returns `hi-` and `slug('!!!')` returns `-`. The goal is `slug(s, max)`: a second positional argument `max` (absent or `undefined` means no limit) cuts the result to at most `max` characters by a plain character-count cut, and the result never ends with a dash, whether cut or not, whether `max` is given or not. Edge input (empty string, only symbols, `max` 0) returns the empty string with no error. An invalid `max` (negative, not an integer, not a number) throws `RangeError`. Leading dashes stay as today (`slug('!hi')` returns `-hi`). With no `max`, or `max` above the slug length, output equals today's output minus a trailing dash. There is no test suite today, so tests are written first. `RULES.md` already states `slug(s, max) cuts the result to max characters and never returns a value that ends with a dash.` and needs no change.

## Parts, in dependency order

### Part 1: write the test file (lands alone, red on new behaviour)

Depends on: nothing.

Creates: `slug.test.js`.
Changes: nothing.
Deletes: nothing.

Content: a Node test file using only built-in modules (`node:test`, `node:assert/strict`; see open point O1) that requires `./slug.js` and asserts every row of the table below. Each row is one test with the name in the first column.
