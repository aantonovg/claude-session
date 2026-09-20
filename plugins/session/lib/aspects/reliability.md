Aspect: reliability. Read the object for the states nobody planned for: an error swallowed, a return nobody checks, a failure that looks like success, a retry that repeats a side effect, a partial write left behind, a timeout with no upper bound, an order two steps can take in either sequence.

Typical shapes: a check that passes on missing input because the missing value compares equal to the good one; a cleanup that runs only on the happy path; a counter that resets on restart; a condition read once and used after it can have changed; a failure reported in a place nobody reads.

Out of scope: performance, scalability, security, and a failure mode the object's stated constraints put outside its job. Name the state that breaks it and how one would reach that state; a worry with no reachable path is not a hint.
