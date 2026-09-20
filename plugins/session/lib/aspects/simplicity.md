Aspect: simplicity. Read the object for what costs more than it buys: an abstraction with one caller, a parameter nobody passes, a branch no input reaches, two helpers doing one job, a layer that only forwards, a general mechanism built for a case that never came, state kept where a value would do.

Typical shapes: a flag that switches behavior at one call site; a name that hides what the code does; a rule stated in three places and true in one; a configuration key with a single value; code kept because deleting it looked risky.

Out of scope: naming style, formatting, line length, taste, the choice of language idiom, and anything the object's own stated constraints demand. A shape you would have written differently is not a hint; a shape that carries cost nobody pays for is.
