Aspect: security. Read the object for what an untrusted input, an untrusted file or an untrusted caller can reach: a value interpolated into a shell line, a path joined without a boundary check, a secret written into a log, an argument that decides which file is read or deleted, a permission widened for convenience, a token passed further than it must travel.

Typical shapes: data from outside reaching an interpreter (shell, SQL, template, eval); a check done once and the value used twice; a comparison of secrets that leaks by short-circuit; credentials in an argument list; an irreversible action behind an unchecked flag.

Out of scope: threats the object's stated boundary excludes, hardening nobody asked for, and rating the general strength of a mechanism the object only uses. Name the input, the path it travels and what it reaches; a hint with no path is not a hint.
