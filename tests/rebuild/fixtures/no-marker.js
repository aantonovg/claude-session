// Build fixture: no marker of any kind. bin/build.sh must leave this file byte-identical.
const T = { class: 'c3', note: 'no shared block, no class table, no roles, no aspects' }
const untouched = () => T.note
