Task: in the current directory slug.js turns a string into a slug and must also cut the result to a maximum length, never ending with a dash.
Depth: std
Acceptance criteria:
1. The slug length is never greater than the maximum length.
2. The slug never ends with a dash, also after the cut, and also with no maximum given.
3. With no maximum given, or a maximum above the slug length, the output is the same as today except that a trailing dash is removed; there is no existing test suite, so new tests are written first.
4. Edge input (empty string, only symbols, maximum 0) gives an empty string, no error and no dash.
Open decisions:
- Parameter name: default `max`, positional second argument; absent (`undefined`) means no limit. Rests on RULES.md, which already says `slug(s, max)`, so no doc change.
- Trailing dash with no maximum: default always stripped (`slug('hi!')` becomes `hi`, `slug('!!!')` becomes empty). Rests on RULES.md and criteria 2 and 4; today these return `hi-` and `-`.
- Where the cut falls: default a plain cut at the character count, then trailing dashes removed; not at a word boundary. Rests on the task text ("cut to a maximum length").
- Invalid maximum (negative, not an integer, not a number): default throw RangeError. Rests on no caller existing in the repository.
- Leading dashes (`slug('!hi')` gives `-hi`): default left as today. Rests on the task and RULES.md naming only the trailing dash.
Review aspects: reliability, simplicity (cut or extend)
