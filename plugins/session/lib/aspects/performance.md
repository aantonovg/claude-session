Aspect: performance. Read the object for work done more often than the result is used: a read inside a loop that could stand outside it, a whole file loaded to answer one question, a repeated call with the same argument, a scan where an index or a map exists, a wait that holds a costly context open while nothing happens.

Typical shapes: quadratic work over a list that grows with the input; a command run once per item instead of once per batch; data copied between stages that could be passed by path; an early exit nobody takes; a cache that never hits because its key carries a timestamp.

Out of scope: micro-optimisation of code that runs once, guesses with no measurement, and limits the object's stated constraints accept. A hint names the input size at which the cost bites and the measurement that would show it.
