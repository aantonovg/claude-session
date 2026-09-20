Aspect: testability. Read the object for the claims nobody can check: a decision buried where no test can reach it, a pure rule mixed into a side effect, a behavior provable only by running a whole session, a check that passes whatever the code does.

Typical shapes: logic inside a file no harness loads; a test that asserts the code as written instead of the wanted behavior; a check with no failing case, so a mutation of the code leaves it green; output nobody can compare because it carries a timestamp; an assertion on a message string that says nothing about the result.

Out of scope: coverage numbers, the choice of harness, tests for code the object's scope excludes, and demanding a test where the verification plan already recorded that no oracle is possible. A hint names the claim and the shape that keeps it out of reach.
