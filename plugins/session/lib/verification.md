# Verification first

One page. Every process skill, every composite workflow and the base text cite it; nothing else
states these rules. It decides, for one object, who checks it and who writes it.

## 1. Good tests beat a good review

1. **Output with an oracle gets no review.** Code covered by tests, a script with a runnable
   check, a config with a validator: the verifier is the oracle, run by an executor. No code
   review and no other review of that output, at any depth.
2. **Output without an oracle gets a stronger author, not a second reader.** For an object only a
   reading could check (a decision contract, a plan, a process document, code with no possible
   verifier), the author runs one slot up in the same class row; the class never moves for a
   stage. A second reader of the same class is waste.
3. **Review is not a default role, but a key document is never unchecked.** No reviewer is paired
   with every author. Every key document (plan, decision contract, specification, closure report)
   gets a checker one slot up in the same class row above its author before the user sees it. The
   stronger author of rule 2 does not replace that check.
4. **The plan names the oracle per object.** Each invariant and each claim carries one of three
   oracle classes: `existing oracle`, `missing oracle`, `no possible oracle`. The class decides the
   route, and no object goes into work without one.
5. **What stays unverified is said.** Weak-oracle areas are listed, named to the user and accepted
   by the user. They are never covered by an opinion instead.

**Fork exception to rule 3.** A fork carries the whole conversation, so its context is biased: a
fork's output always goes to a clean-context checker, whatever the ladder level says. This is the
one case where an author's carrier, not the object, forces the check.

## 2. Oracle class and route

| oracle class | what it means | route |
|---|---|---|
| existing oracle | a check exists and runs today (tests, a validator, a control call file, a build) | run it through an executor; the run output is the verdict; no review of that output |
| missing oracle | a check is possible but absent | build the check first, at the level above the object, then run it; the cost of building it is part of the task, not an extra |
| no possible oracle | no runnable check can exist (intent, a plan, a prose document) | rule 2 (author one slot up in the same class row) plus, for a key document, rule 3 (checker one slot up in the same class row above that author), carried by the evidence review chain |

An object whose class is unclear is treated as `missing oracle` until someone shows no check can
exist; the cheap mistake is building a check that was not needed, the costly one is an opinion
standing in for a run.

## 3. The ladder: levels a-e

From the strongest oracle to the weakest. The route of an object follows its level; the question
is never "should this be reviewed", it is "which level is this".

| level | object | oracle class | oracle | route |
|---|---|---|---|---|
| a | code | existing or missing | tests and benchmarks; almost always possible | an executor runs them; no review of the code; a missing suite is written first (level c) |
| b | infrastructure change, local or remote | missing, then existing | the resulting state: requests against it, metrics, logs | control calls written before the change (section 5), run by an executor before it and after it; the pair of runs is the verdict |
| c | tests, benchmarks, harness code | no possible oracle for quality, existing for coverage | the scenario list written beforehand | coverage only: every scenario has a test, no test stands without a scenario, read by a coverage check of the two lists. No quality review. At depth `full` a negative control: the test must fail without the change |
| d | test scenarios as text | existing, against the level above | the fixed specification: goal, subtasks, functional and non-functional requirements, invariants, constraints | traceability: every requirement, invariant and constraint has at least one scenario, negative ones included; a gap goes through the evidence chain, not through an opinion |
| e | intent: which problem the user wants solved, what to change | no possible oracle | only the user | a critic looks for ambiguity, a contradiction, a hidden second goal; the user confirms the text. At `std` and `full` no stage starts before that confirmation; at `lite` the session acts at once on its own reading; nothing but research is launched before that confirmation |

The lower the level, the weaker the oracle, the more a check costs and the more the user is needed.

## 4. The artifact chain

The same ladder read from the top is the order in which a task is worked, for code and for
non-code work alike:

intent (goal) → subtasks, when the goal is complex → functional requirements, non-functional
requirements, invariants, constraints → test scenarios as text → verification plan →
implementation plan → executable tests, or manual control calls → the result (code, infrastructure
state, document).

**Each level is the oracle for the level below it.** A level is checked against the level above,
never against the conversation and never against the author's memory.

| level | checked against | check | author |
|---|---|---|---|
| intent, with quality criteria | the user | dialogue; critic hints on ambiguity; the user confirms the text. User gate at `std` and `full` | the main session with the user |
| subtasks | intent | every part of the goal has a subtask, no subtask lies outside the goal; evidence chain; user gate at `std` and `full` | one slot up in the same class row |
| requirements, invariants, constraints | intent and subtasks | traceability to the subtasks, no contradiction, every non-functional requirement in a measurable form; evidence chain | one slot up in the same class row |
| test scenarios as text | the specification | traceability: every requirement and invariant has scenarios, negative ones included; a critic only for missing cases | one slot up in the same class row: coverage is checkable, the sense of a scenario is not |
| verification plan | the scenarios | every invariant has an oracle row: `existing`, `missing` or `no possible` | one slot up in the same class row |
| implementation plan | the verification plan | the steps and their order are named and checked against the verification plan; starts only after the verification-plan gate passed | one slot up in the same class row |
| executable tests, control calls | the scenarios | coverage by reading the two lists; negative control at `full`; no quality review | no uplift, the cheapest author the class allows |
| result: code, infrastructure state | the tests, the control calls | an executor runs them | no uplift, the cheapest author the class allows |
| result with no possible oracle (a document) | the scenarios, read as a checklist a reader can answer | evidence chain with aspect critics | one slot up in the same class row |

Two consequences:

- An error high in the chain is the most costly one: every level below verifies against it
  faithfully, and a wrong intent gives green tests for the wrong thing. So the money and the
  user's attention go to the top of the chain and the bottom runs cheap.
- At depth `lite` the top levels collapse into one short text (intent, subtasks and requirements
  together, scenarios as one-liners), but their order and the rule "checked against the level
  above" stay.

The form of the scenario text is free: the author picks it per task. Known forms are hints only
(Gherkin, EARS, plain one-liners). No scenario carries an id and no test name carries one: an
extra link between two texts drifts apart as soon as one of them changes, so coverage is checked
by reading the two lists.

## 5. Ops work: control calls are the tests

For an infrastructure change, local or remote, the accepted form of "tests" is a file of control
calls: each line one command with its expected result (a request and the answer it must give, a
metric and its band, a log line that must appear or must never appear). The file is written
**before** the change, run before it to record the state it starts from, and run again after it.
The pair of runs is the verdict; a call whose expected result was not written down beforehand
proves nothing. An ops object whose control calls cannot be written is a weak-oracle area and goes
through section 6.

## 6. How an unverified area is accepted

An area with no possible oracle, or with an oracle nobody can run here, is not silently reviewed
away. It is:

1. named in the verification plan with its oracle class and the reason no run is possible;
2. given the strongest available substitute: the author one slot up in the same class row (rule 2)
   and, for a key document, the evidence review chain one slot up in the same class row above the
   author (rule 3);
3. listed in the report as unverified, in the user's words, with what a later run would need;
4. accepted by the user, explicitly. The user's acceptance is the closing act, not a judgment of
   the session about its own output.

A finding without evidence never becomes an accepted defect, and an unverified area never becomes
a verified one because a reading went well.
