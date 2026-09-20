# Subagent work aspects: structured idea

Source: the user's note "Аспекты работы субагентов" (2026-09-18). This document
structures the note, names its goals, the problems it solves, the expected gains, the
gap against the current `session` plugin and the subtasks of an implementation.

Revision 2 (2026-09-18), after the user's first reading. Added from the feedback: the
class `c1-c5` as the only source of model and effort (3.4), the verification-first rule
(3.5), review as an evidence chain of four roles (3.6). Terms and concepts are reused
from the two process skills that already exist, `session:pipeline` and `session:review`
(gates, paths as hard lists, ceilings, oracles, the heavy document cycle). Sections 4-9
follow the new rules.

Revision 3 (2026-09-18), two more additions from the user: aspect critics (3.6); the
verifiability ladder and the artifact chain from intent to executable tests (3.5.1,
3.5.2), depth and class as two independent axes, and quality criteria agreed with the
user at intent level as the source of the aspect set (3.3).

## 1. Idea in short

The work of a subagent has four independent aspects: which tools it has, which role it
plays, how several roles cooperate on one task, and how one piece of a task is worked
through. Today these aspects are mixed: an agent file carries both the tool list and the
role, the main model writes role prompts on the fly, and the order of roles on a big
task is chosen by the main model each time.

The idea separates the aspects and gives each one its own carrier:

| aspect | carrier |
|---|---|
| tool set | named lean agent (agent file) |
| role | workflow (static prompt inside the script) |
| fixed process on a piece of a task | longer workflow over a pool of agents |
| process of several roles on a whole task | skill that describes stages and which workflow each stage needs |

One setting crosses all four: the class `c1-c5`, set once at session start. It alone
decides the model and effort of every agent in every workflow.

The main model stops inventing prompts, process, models and review opinions. It picks a
process, picks a depth, launches named workflows with arguments, and records the results
in a task file group.

## 2. The four aspects

### 2.1 Tool set (lean agents)

A subagent must see only the tools its job needs. Fewer tools mean a smaller system
prompt, a lower cost per cold agent, and less room for the agent to leave its job
(a critic without Edit cannot "fix while reading").

### 2.2 Role (static prompt)

A role is a static prompt: who the agent is, what it returns, what it never does. The
key property in the note: the role text is **not written by the main model at launch**.
A prompt written on the fly differs from run to run, costs main-model output tokens, and
drifts with the conversation. A static role is checked once and then reused.

### 2.3 Process of several roles on one task

Two sub-points from the note:

- Tasks differ strongly by type (bugfix, feature, research, migration, ops, document,
  review of someone else's MR). Each type needs its own sequence of roles, so there are
  several processes, not one. The plugin already shows this: `session:pipeline` (own
  task) and `session:review` (someone else's work) share a core and differ in stages.
- The work on a task is not one continuous run. It stops for a direction change or a
  human review and then continues. So this level cannot be one long workflow script: a
  script runs to the end and has no place for the user. It must be a description that the
  main session follows stage by stage, with state on disk between stages.

### 2.4 Fixed process on a piece of a task

Inside one stage the order of steps is known in advance (author, tests, fixer, up to N
cycles; or critic, evidence, triage, fixer). This part needs no human and no judgment by
the main model, so it is a deterministic script.

## 3. Proposed mechanisms

### 3.1 Tool set through named agents

- A family of named agents that differ only by tool combination, from the simplest
  (Read only; Read and Write) to richer ones (Bash, Read, Edit, Write; web; MCP).
- The agent file holds the tool list and a minimal common contract (return shape,
  BLOCKED rule, working directory rule). It holds no role and no model.
- Tools that exist only inside one project or a group of projects (project MCP servers,
  project CLIs) get their agent files in the plugin of that project group, not in the
  common plugin. The common plugin stays free of project names.

### 3.2 Role at the workflow level

The role lives in the workflow script, not in the agent file. Two kinds of workflows:

- **Short workflow, single agent.** One `agent()` call with a static role prompt and
  typed arguments (paths, question, output file). The workflow turns a neutral tool-set
  agent into a role agent: `critic`, `researcher`, `executor`, `translator`, `triage`.
  The main session launches it by name and passes only arguments.
- **Longer workflow, agents pool.** Several role calls in a fixed flow that solves one
  subtask: author → tests → fixer with a cycle limit; parallel researchers → critique →
  synthesis; critic → evidence-researchers → triage → fixer. This is aspect 2.4.

### 3.3 Process skill

The process of several roles on one big task is a skill. The two existing process
skills already show the working shape, and the new skill keeps it:

- **Stages with gates.** Each stage ends at a gate with a written pass condition
  (pipeline: R research, D decision, V verification, I implementation, F closure check,
  C closure). A gate is where the user may review and where a direction change returns
  the task to an earlier stage (a changed assumption goes back to the decision contract).
- **Workflow per stage.** The skill names which workflow (role or pool) each stage
  launches and with which arguments. The main session dictates decisions as short
  bullets; it writes no role text.
- **Several processes.** One process table per task type: code change, investigation,
  document, ops change, review of someone else's MR. Shared rules (task directory,
  ledger, cost rules, harness gate, `Sources` and `Oracles` blocks) live in one core
  file that every process reads first, as `pipeline/core.md` does today.
- **Depth levels `lite`, `std`, `full`.** A depth is a hard list, not a mood: a step
  marked `–` is not done at all, even when it looks useful. Each depth has ceilings
  (agents, cycles, turns); a hit ceiling ends the stage and the gap goes into the report.
  The main session proposes class and depth in one line and starts; an argument fixes
  the depth.
- **Two independent axes.** Every long process of this kind has a weight `lite`, `std`
  or `full` in addition to the class `c1-c5`. The depth says which stages and artifact
  levels run and with which ceilings; the class says on which model and effort each
  role runs (3.4). Neither is derived from the other: `full` at `c2` (every stage,
  cheap models) and `lite` at `c5` (few stages, strong models) are both valid.
- **Intent first, with quality criteria.** The first stage of every process fixes the
  intent with the user (3.5.2). In the same talk the quality criteria of the solution
  are defined and agreed: which of simplicity, extensibility, reliability, performance,
  security and the like matter for this task, in which order, and which do not matter.
  They are recorded in the task files next to the intent. Every later stage reads them:
  authors as constraints, the review chain as the default source of its aspect critics
  (3.6, "Aspect critics"), triage as the scale for severity.
- **Task file group.** Framing, ledger (unknowns by class: decision-changing,
  verification-changing, implementation-local, nice-to-know), evidence bundles, decision
  contract, verification plan, implementation plan, reviews, report. The files carry the
  state between stages, across interruptions, across `/compact` and across sessions.
  Workflows take them by path and write into them. Every stage returns a short
  structured status (`Status`, `Evidence`, `Assumptions`, `Unresolved`, `Next`); `done`
  needs evidence.
- **Harness gate.** Before the work starts, the tools the process needs are
  health-checked; a wanted tool that is unavailable is named in chat, not silently
  skipped.
- **Limit on main-model improvisation.** The skill tells the main model what to launch
  and what not to launch: a forbidden list, loop guards (the same check fixed twice →
  stop and write a failure packet), no extra cycle without the user's word.

### 3.4 Class drives model and effort

The class `c1-c5` is set at session start and holds for the session. Rules:

- Every role belongs to a slot (main-model, opus, sonnet). The class row of the base
  table, then the submodes (`no-sonnet`, `no-opus`, `no-fable`), give the model and
  effort of that slot. Nothing else does.
- Every workflow, short or pool, takes `class` and `submodes` as arguments and resolves
  each `agent()` call through the table. The main model passes the session's class; it
  never chooses a model or effort by feel, and no role text or skill text names a model.
- The slot of a role follows from the kind of work: volume of input (large input moves
  a role one slot down), number of mechanical queries (many → cheap), and whether the
  output can be verified (3.5).
- A critic may raise the task class, never lower it (as in `pipeline`). A raise applies
  to the stages that follow.
- The label of each agent shows the resolved cell (`<mod>-<eff>-<job>`), so a transcript
  proves the class was followed.

### 3.5 Verification-first rule

Good tests are always stronger than a good review. From this:

1. **Output with an oracle gets no review.** Code covered by tests, a script with a
   runnable check, a config with a validator: the verifier is the oracle (tests,
   scenarios, static checks, CI job), run by an executor. No code review and no other
   review of that output, at any depth. Tests and harness code cannot be tested by other
   tests (a tautology); they are written cheap and get no quality review, only a
   coverage check against the scenario list (3.5.1, level c) and, at depth `full`, a
   negative control (the test must fail without the change).
2. **Output without an oracle gets a stronger author, not a second reader.** For an
   object that only a review could check (a decision contract, a plan, a process
   document, code with no possible verifier), the author runs one step higher than the
   author of testable code. A second reader of the same class is waste. `pipeline`
   already applies this to no-verifier packages.
3. **Review is not a default role.** The target design has no reviewer paired with every
   author. The one exception: the author is a fork. A fork carries the whole
   conversation, so its context is biased; its output goes to a clean-context agent.
   This is why the pipeline's critic is cold: framing, ledger and contracts there are
   written by forks.
4. **The plan names the oracle per object.** The verification plan maps each invariant
   or claim to an oracle (`existing oracle`, `missing oracle`, `no possible oracle`, the
   rows of the review contract in `session:review`). The row decides the route: run,
   build the missing check and run, or rule 2.
5. **What stays unverified is said.** Weak-oracle areas (ops, visual) are listed and the
   user accepts them; they are not covered by an opinion.

#### 3.5.1 Verifiability ladder

Objects differ by how strong an oracle they can have. From the best oracle to the worst:

| level | object | oracle | check |
|---|---|---|---|
| a | code | tests and benchmarks; almost always possible | an executor runs them; no review |
| b | infrastructure change, local or remote | the resulting state: GET requests against it, metrics, logs | control calls written before the change, run by an executor before and after it |
| c | tests and benchmarks | the list of wanted test scenarios, written beforehand as text (Gherkin, EARS or informal) | coverage only: every scenario has a test, no test stands without a scenario. Not a review of quality. Negative control at `full` |
| d | test scenarios | the fixed specification: goal and subtasks, functional and non-functional requirements, invariants, constraints | traceability: every requirement, invariant and constraint has at least one scenario, negative ones included; gaps go through the evidence chain (3.6) |
| e | intent: which problem the user wants solved, what to implement, which system to change | only the user | the review process (a critic looks for ambiguity, contradiction, a hidden second goal) and a talk with the user that clarifies intent, goal and subtasks |

The lower the level in the table, the weaker the oracle, the more a check costs and the
more the user is needed. The ladder decides the route of every object in a process: the
process skill never asks "should this be reviewed", it asks "which level is this".

Coverage at level c can be made mechanical: each scenario gets an id, each test carries
the id of its scenario in its name or a tag, and a script lists scenarios without a test
and tests without a scenario. An agent (`coverage-checker`, sonnet slot) reads only the
residue the script cannot match.

#### 3.5.2 Artifact chain

The same ladder, read from the top, is the order in which a task is worked. It holds
for non-code work too (a document, an ops change, an investigation):

intent (goal) → subtasks (a decomposition, when the goal is complex) → functional
requirements, non-functional requirements, invariants, constraints → test scenarios as
text → executable tests in a language, or manual scenarios of control calls → the result
(code, infrastructure state, document).

**Each level is the oracle for the level below it.** A level is checked only against the
level above, never against the conversation or the author's memory. From 3.5 follows the
author of each level: where the check is only a review, the author goes up.

| level | checked against | check | author |
|---|---|---|---|
| intent, with quality criteria | the user | dialogue; critic hints on ambiguity; the user confirms the text. User gate at every depth | main session with the user; the text is written on the main-model slot |
| subtasks | intent | every part of the goal has a subtask, no subtask lies outside the goal; evidence chain; user gate at `std` and `full` | uplift: main-model slot |
| requirements, invariants, constraints | intent and subtasks | traceability to subtasks, no contradictions, every non-functional requirement has a measurable form; evidence chain | uplift: one step above the code author |
| test scenarios as text | the specification | traceability by id: every requirement and invariant has scenarios, negative ones included; mostly a script, critic only for missing cases | uplift: one step above the code author (coverage is checkable, the sense of a scenario is not) |
| executable tests, control calls | the scenarios | coverage by id; negative control at `full`; no quality review | no uplift: cheap author |
| result: code, infrastructure state | the tests, the control calls | executor run | no uplift: the cheapest author the class allows |
| result with no possible oracle (a document) | the scenarios, as a checklist a reader can answer | evidence chain with aspect critics | uplift: one step above the code author |

Two consequences:

- An error high in the chain is the most costly one: every level below verifies against
  it faithfully, and a wrong intent gives green tests for the wrong thing. So the money
  and the user's attention go to the top of the chain, and the bottom runs cheap.
- The chain maps onto the existing pipeline files: `Framing` is the intent, the
  invariants of the `Decision contract` are part of the specification, the
  `Verification plan` (invariant → oracle map, scenarios, negative scenarios) holds the
  scenarios, the harness holds the tests. What the pipeline lacks is listed in section 7.

At depth `lite` levels collapse (intent, subtasks and requirements in one short text,
scenarios as a list of one-liners), but their order and the rule "checked against the
level above" stay.

### 3.6 Review as an evidence chain

Where a review does run (rule 3 of 3.5, or a review of someone else's work), a reviewer
does not produce correct judgments. It can only point at places where an error may
hide. Each point is then proved or refuted by facts. Four roles, one pool workflow:

| stage | role | what it does | slot |
|---|---|---|---|
| 1 | `critic` | reads the object in a clean context; writes hints: place, suspected error, severity, what evidence would settle it. Hints, not verdicts. Read and Write only, tool-call budget. | main-model |
| 2 | `evidence-researchers` | parallel, one per hint or group of hints; collect facts by research, test runs, a run on the base version, docs. Return `confirmed`, `refuted` or `undetermined` with pointers. Many cheap queries. | sonnet |
| 3 | `evidence-triage` | the judge: reads the critique and the evidence, accepts or rejects each hint, writes the accepted list with the required change. Runs no queries itself. | main-model (or opus, open question) |
| 4 | `fixer` | changes the object by the accepted list only; then the oracle runs when one exists. | opus |

Rules of the chain:

- A hint without evidence changes nothing. `undetermined` is rejected or goes to the
  user; it never goes to the fixer.
- Two kinds of failure stay apart (from `session:review`): a finding about the object,
  and a harness failure on our side (tool, access, sandbox). Only the first reaches
  triage.
- A control run guards against false findings: a failure that also shows on the base
  version is not a finding.
- One round: generate → critique → evidence → triage → fix, no second critique without
  the user's word (the heavy document cycle of `pipeline`).
- Short form for depth `lite` and `std`: stages 2 and 3 merge into one `evidence` agent
  on a lower slot that both collects and decides (the pipeline's evidence-audit). Long
  form for `full` and for a high severity.

**Aspect critics.** Stage 1 may split into several parallel critics. Each one reads the
same object through one quality aspect and gives hints only on that aspect: simplicity,
reliability, security, extensibility, performance, scalability, and similar (testability,
operability, data integrity, cost). A narrow question finds more than a general "look
for problems", and the aspects do not compete for one critic's attention or tool budget.

- **Aspect set per task.** Not every aspect fits every object: a process document has no
  performance aspect, an internal script has no scalability aspect. The set is chosen
  for the task. Its default source is the list of quality criteria agreed with the user
  at intent level and recorded in the task files (3.3): a criterion the user named
  becomes an aspect critic, a criterion the user ruled out is never launched. Default
  count by depth (a proposal, not settled): `lite` one merged
  critic with no aspect split, `std` 2-3 aspects, `full` 3-5 aspects.
- **Static aspect prompts.** The workflow holds one common critic role text (clean
  context, hints not verdicts, the hint format, the budget) plus one short static
  paragraph per aspect: what the aspect means, the typical error shapes, what is out of
  scope. The `aspects` argument is a list of names from that fixed catalog; it selects
  paragraphs and carries no prompt text. An unknown name stops the workflow. A new
  aspect is a new paragraph in the script, checked once.
- **Hint format.** Every hint carries `aspect`, `place` (file and line range, or
  document section), suspected error, severity, and the evidence that would settle it.
  Each critic has a hint cap (proposal: 5), so N critics give at most 5 × N hints.
- **Merge and dedupe, in the script.** No extra agent. The script concatenates the hint
  lists and groups them by `place`; hints on the same or overlapping place form one
  group that keeps all its aspect tags. One group goes to one evidence-researcher, so
  two critics that point at the same lines cost one evidence run, not two. The group
  takes the highest severity of its hints. Same-meaning hints on different places stay
  separate; triage sees the whole list with tags and can accept them as one change. A
  place named by several aspects is a useful signal for triage, not noise.
- **Slot under the class table.** Aspect critics resolve through the table as every
  role does; no aspect has its own model. Proposal: the single merged critic stays on
  the main-model slot; when the stage splits into 2 or more aspect critics, each runs
  on the opus slot, because a narrow question needs less from the model and the costly
  read would otherwise multiply by N. Large input moves them one more slot down by the
  usual rule. `evidence-triage` stays the one costly judgment over all aspects.
- **Cost.** The critic stage costs N × (one read of the object plus a short hint list);
  the split multiplies the read, which is why the slot goes down as N goes up. The
  evidence stage grows with the number of hint groups, not with the number of critics,
  and the hint cap bounds it. Ceilings per depth count aspect critics as agents. For a
  small object at depth `lite` the split costs more than it finds; one merged critic is
  the rule there.

The gain: model choice per stage (one costly read or several cheaper narrow reads, many
cheap searches, one costly judgment), and a change of the object rests on facts, not on
a model's guess.

## 4. Goals

1. One carrier per aspect: tools in agent files, roles in workflows, fixed flows in pool
   workflows, the task process in a skill.
2. Remove prompt writing from the main model: launches carry arguments, not role text.
3. Model and effort of every agent come from the session's class and the role's slot,
   never from a choice made at launch.
4. Verification by oracle first: review runs only where no oracle is possible and the
   author's context is biased.
5. A review changes the object only through evidence: hint → facts → judgment → fix.
6. Make the work on a task repeatable: the same task type and depth give the same stages,
   the same roles and the same artifacts.
7. Make the work interruptible: a task can stop for the user and resume from files.
8. Match spending to the task on two independent axes: depth (`lite`, `std`, `full`)
   decides what runs, class (`c1-c5`) decides on which models.
9. Keep project-specific tools out of the common plugin.
10. Work down one artifact chain, for code and non-code tasks: intent → subtasks →
    requirements and invariants → test scenarios → executable tests → result. Each level
    is checked only against the level above, by the check its ladder level allows.
11. Agree the intent and the quality criteria with the user before anything is built,
    and let the criteria steer the later checks.

## 5. Problems it solves

- **Role drift.** The main model writes a new critic or researcher prompt each time;
  quality and return format differ between runs.
- **Output-token cost of launches.** A 300-1000 token prompt per agent is written by the
  most expensive model. With static roles the launch is a name plus arguments.
- **Agent-file explosion.** When role and tool set live in one file, every new role needs
  a new agent. Separated, N tool sets and M roles give N + M files, not N × M.
- **Model chosen by feel.** The main model picks a model and effort per launch; the same
  role runs on different models in one session and the class set by the user is not
  followed.
- **Review where tests are stronger.** A code review of tested code costs a full read on
  an expensive model and proves less than the test run.
- **Review opinions treated as facts.** A reviewer's remark goes straight to a fixer; a
  wrong remark damages a correct object and costs a fix cycle.
- **Weak authors for unverifiable objects.** A plan or contract written on a cheap slot
  and then "saved" by a reviewer costs two runs and is still unproved.
- **Improvised process.** The main model decides on the fly whether to research first,
  how many cycles to run. It over-spends on small tasks and under-spends on risky ones.
- **One-shot workflows cannot be steered.** A full development workflow runs from plan to
  closure with no point for a direction change or human review.
- **Lost state.** Without a fixed file group the state of a task lives in the
  conversation; a compact, a new session or a limit restart loses it.
- **Project tools in a common plugin.** Agents with project MCP tools do not belong in a
  plugin that every project loads.

## 6. What gets better after implementation

Targets; a baseline must be measured first (transcripts under `~/.claude/projects`).

- Main-session output tokens per agent launch: from 300-1000 (prompt text) to under 100
  (name and arguments).
- Share of launches by name against ad hoc scripts: over 80 %.
- Class compliance: 100 % of agent labels match the cell of the session's class and the
  role's slot.
- Reviews of output with a passing oracle: zero.
- Fixes without accepted evidence: zero; every change made by a fixer points to a triage
  line, and that line to an evidence pointer.
- Hint precision: share of critic hints confirmed by evidence is measured per process;
  a low share is a signal to change the critic's prompt, not to add a second critic.
- Rework caused by a wrong review remark: drops, since a refuted hint never reaches the
  fixer.
- Cost of a review chain against a single expensive reviewer-plus-fixer pair: equal or
  lower, since the many queries run on the sonnet slot.
- Cost per task by depth: `lite`, `std`, `full` have stated ceilings; the ledger row
  count is checked against them.
- Rework after a late finding: a gate after the decision stops a wrong direction before
  implementation.
- Resume: a task continues after `/compact`, a new session or a limit restart from the
  task files with no re-research.
- Maintenance: a role changes in one workflow file; a tool set in one agent file; a
  process in one skill; the model map in one table.

## 7. Gap against the current `session` plugin

Checked: `plugins/session/agents/`, `workflows/`, `workflows/dev.js`,
`skills/pipeline/SKILL.md`, `skills/review/SKILL.md`, the base skill. Workflow
internals other than `dev.js` are taken from their contracts, not from the scripts.

**Already there**

- Lean agents with reduced tool lists: `stage-author` (Bash, Read, Edit, Write),
  `stage-reviewer` and `stage-critic` (Read, Write), `stage-executor` (Bash, Read),
  `stage-researcher`, `translator`, `waiter`, `web-researcher`.
- Pool workflows with a fixed flow: `dev`, `build`, `review-fix`, `research`. Role
  prompts are static text inside the scripts; `class` and `submodes` are arguments and
  the class table resolves model and effort per slot.
- One short workflow close to the single-agent kind: `translate-ru`.
- Workflow contracts reach the main session as SessionStart context.
- Two process skills with the target shape: `session:pipeline` (gates R, D, V, I, F, C;
  paths fast, standard, full as hard lists with ceilings; task directory, ledger,
  evidence bundles) and `session:review` (paths `lite`, `std`, `full`, `re`; review
  contract with oracle rows; findings only from runs; control run on the base branch).
- Verification-first is written in both: "There is no code review in this mode", a
  no-verifier package gets a stronger author and no reader, tests are never reviewed.
- A partial evidence chain: pipeline's cold critic → main-session triage →
  evidence-audit fork → low fixer fork, one round; `review-fix` names "critique,
  evidence check, fixes, tests" in its contract.

**Missing or mixed**

- The base skill contradicts verification-first: "every authoring stage pairs with an
  independent review", code review of every diff over 100 lines, a plan critique and a
  closure review as the minimum for every code task. `dev` and `build` follow the base,
  not the pipeline.
- No `evidence-triage` role. In `pipeline` the main session triages by itself, on its
  own judgment and in its own context; evidence is one fork, not a group of cheap
  researchers. No pool workflow runs the four-stage chain for an arbitrary object.
- `stage-reviewer` exists as a role with verdicts; the design wants a critic that gives
  hints and leaves verdicts to triage.
- The stronger-author rule is hard-coded as model names ("opus-low", "terra-high") in
  `pipeline`, not as "one step up" from the class table. `session:review` fixes its
  main session to opus-low in text. Both break "no model names in skills".
- Fork stages in `pipeline` and `review` inherit the main session's model, so the class
  does not drive them; only cold stages follow the table.
- Agent files still carry roles in names and bodies ("author", "reviewer", "critic");
  the tool-set family is not named by tools and is not complete (no Read-only agent, no
  MCP variants).
- No short single-agent role workflows for the common roles (critique of one document,
  one research question, run one test command, triage). The base skill tells the main
  session to write an ad hoc script with a 300-1000 token prompt instead. This is the
  largest gap.
- `pipeline` and `review` run stages through forks with prompts dictated by the main
  session, not through named workflows; roles are still written on the fly.
- `dev` is a one-shot run from plan to closure with no stop for the user.
- Process tables exist for own code task and MR review only; investigation, document
  and ops are named in the pipeline description but have no table.
- Depth names differ (`fast/standard/full` against `lite/std/full`) and depth is derived
  from class in both skills.
- Two task file locations and shapes: `~/.claude/projects/.../pipeline/<task>` for the
  skills, `<cwd>/reviews` for workflows.
- No project-group plugin pattern (the b2connect agents live in the project's `.claude`,
  which fits the idea but has no tool-set naming).
- The shared block (class table, `opts`, `cycle`) is copied into every script; more
  short workflows multiply the copies.
- A workflow does not check that a stage's output file exists (seen today in
  `translate-ru`: the agent returned the path and wrote nothing). A `done` without
  evidence passes.
- The artifact chain is only partly there. `pipeline` has `Framing`, a `Decision
  contract` with invariants and a `Verification plan` with an invariant → oracle map,
  but: no gate where the user confirms the intent (the main session proposes and
  starts); no specification level of its own (functional and non-functional
  requirements, constraints); scenarios have no fixed text form and no ids; no coverage
  check of tests against scenarios (the fast path writes "one new test per changed
  behaviour" with no scenario list). `dev` starts in the middle of the chain: it takes
  "a task with acceptance criteria" and nothing checks the criteria against an intent.
- No ladder: the skills know two cases (has a verifier, has none). Infrastructure
  changes have no named check by control calls against the resulting state; `pipeline`
  only calls ops a weak oracle.
- Quality criteria of the solution are not asked for, not recorded and not used; the
  critic reads without a scale agreed with the user.

## 8. Implementation subtasks

Order follows the dependencies; items at the same level can run in parallel.

1. **Tool-set inventory and naming.** List the tool combinations in real use (agent
   files and transcripts), choose the family and names by tool set, decide the fate of
   the `stage-*` names (rename or alias). Output: a table of agents. Depends on: nothing.
2. **Role catalog with slots.** Roles: plan author, code author, test author, fixer,
   critic, evidence-researcher, evidence (merged short form), evidence-triage,
   researcher, executor, translator, web researcher, and the chain roles of 3.5.2: spec
   author, scenario author, coverage-checker. For each: static prompt, arguments,
   return format, tool-set agent, slot, and the rule that moves the slot (input volume,
   no-oracle uplift). No model names anywhere. Depends on: 1.
3. **Verification-first specification.** Oracle classes (`existing`, `missing`,
   `no possible`), the route per class, the size of the author uplift for no-oracle
   objects, the fork-author exception, how unverified areas are accepted. The
   verifiability ladder (levels a-e) with the check per level, control calls for
   infrastructure changes, and the artifact chain with the author per level. The
   scenario text form (Gherkin, EARS or informal), scenario ids and the id rule for
   tests, the coverage script. One page that the core file and the workflows cite.
   Depends on: nothing.
4. **Shared-block strategy.** A build step that stamps the class table and helpers into
   every script, plus a test that all copies match; the block also carries an
   "output exists" check for every stage that names an output file. Depends on: nothing;
   needed before 5.
5. **Short role workflows.** One script per role from the catalog, each with a usage
   contract and its SessionStart line; `class` and `submodes` as arguments. Test each in
   a tmux session. Depends on: 2, 4.
6. **Review-chain pool workflow.** `critic → evidence-researchers → evidence-triage →
   fixer`, long and short form by a `depth` argument, one round, harness failures kept
   apart, control run, accepted list as a file. Aspect critics: a fixed catalog of
   static aspect paragraphs in the script, an `aspects` argument (list of catalog
   names; default: the agreed quality criteria read from the task files, count by
   depth), parallel critics with a hint cap, script-side grouping of
   hints by place before the evidence stage, the slot rule for a split critic stage,
   aspect critics counted in the depth ceilings. Test: two critics that hint at the same
   lines produce one evidence run. Rework `review-fix` onto it or replace it.
   Depends on: 2, 3, 4.
7. **Pool workflows under verification-first.** `dev` and `build`: remove the reviewer
   from testable code (author → tests → fixer), route no-oracle packages to the stronger
   author, route fork-authored documents to the review chain. Split `dev` at its gates so
   a stage can run alone. Depends on: 3, 6.
8. **Task file group.** One layout for every process and depth: location, file names,
   which stage writes which file, status markers, the resume rule. One artifact per
   chain level: intent with quality criteria (confirmed by the user, with the date),
   subtasks, specification, scenarios with ids, the scenario → test coverage table.
   The collapsed form for `lite`. Align workflow `out` defaults with it. Depends on: nothing; needed before 9.
9. **Process skill on workflows.** Carry over from `pipeline` and `review`: core file,
   gates, hard-list depth table with ceilings, `Sources` and `Oracles` blocks, harness
   gate, loop guard, structured status. Replace fork stages that write role prompts with
   named workflows; keep forks for glue whose input lives in the conversation. Depth
   and class as two independent arguments. Stages follow the artifact chain; the first
   stage is the intent talk with the user (intent, subtasks, quality criteria) and ends
   at a user gate at every depth. First process: code change. Depends on: 5, 6, 7, 8.
10. **More processes.** MR review (port of `session:review`), investigation, document,
    ops change: each a process table over the same core. Depends on: 9.
11. **Base skill cleanup.** Remove "every authoring stage pairs with a review", the
    mandatory code review and closure review; state verification-first, the review
    chain, "class drives model and effort", "launch by name; an ad hoc script is the
    exception". Remove model names from `pipeline` and `review` texts. Depends on: 3, 9.
12. **Project-group plugin pattern.** Template and one real case (b2connect): agent
    files with project tools, role workflows that use them, how the process skill finds
    them. Depends on: 1, 5.
13. **Behavior tests.** `test-session` scenarios: launch by name with no role prompt;
    agent labels match the class cell under c2, c3, c5 and one submode; no review when
    an oracle exists; a seeded false hint is refuted and never reaches the fixer; a
    seeded real defect is confirmed and fixed; `lite` skips what it must skip; a task
    resumes from files after `/clear`; no stage starts before the user confirmed the
    intent; a scenario without a test and a test without a scenario are both reported
    by the coverage check; a quality criterion the user ruled out launches no critic;
    `full` at `c2` and `lite` at `c5` both run as asked. Depends on: 9, 11.
14. **Measurement.** Baseline first, then after, on 3-5 comparable tasks: main-session
    output tokens per launch, agents per task, cost per depth, hint precision, rework
    count. Depends on: 13.
15. **Release.** Version bump, README, memory and skill updates by the release skill.
    Depends on: all above.

First useful cuts: 1 → 2 → 4 → 5 removes on-the-fly role prompts without touching the
process level; 3 → 6 → 11 brings verification-first and the evidence chain to the
present workflows without waiting for the new process skill.

## 9. Open questions for the user

1. Does review disappear as a role? Proposal: yes, `reviewer` is removed; `critic`
   (hints) plus the evidence chain stay, and only for fork-authored or external objects.
   Does a key document by a cold stronger author (plan, decision contract) then go to
   the user with no critic at all?
2. Size of the author uplift for no-oracle objects: one slot up (sonnet → opus →
   main-model), one class up (c3 → c4 for that stage), or a fixed main-model slot?
3. Slot of `evidence-triage`: main-model slot always, or opus slot below `c4`? It reads
   little and judges much.
4. When is the chain long (researchers plus triage) and when short (one `evidence`
   agent)? Proposal: by depth, long for `full` and for any high-severity hint.
5. `undetermined` hints: rejected silently, listed in the report, or sent to the user
   through `session:ask`?
6. Does the new process skill replace `session:pipeline` and `session:review`, or is it
   their next version (same names, stages moved from forks to workflows)?
   Recommendation: next version, one core.
7. Settled by the user: depth (`lite/std/full`) and class (`c1-c5`) are two independent
   axes. Still open: when no depth is given, does the process take a default from the
   class (`c1-c2` lite, `c3-c4` std, `c5` full, as the skills do today), or does the
   main session propose a depth from the task itself (size, blast radius, oracle
   strength)? Recommendation: from the task; the class says nothing about the task.
8. Forks inherit the main model, so the class cannot drive them. Are forks limited to
   glue, with every role stage on a cold workflow agent?
9. Agent names: rename `stage-*` to tool-set names (breaking for saved scripts) or keep
   the names and only strip role text from the bodies?
10. Short workflows: one per role (about 10-12), or one generic `role` workflow with a
    `role` argument? And is a SessionStart contract line per workflow acceptable for
    context cost (50-150 tokens each), or must role workflows share one table?
11. Where does the task file group live: in the repository (`<cwd>/reviews/<task>`) or
    under `~/.claude/projects/.../` as the skills do today?
12. Who picks the aspects for the critic stage? Revised: the default source is the list
    of quality criteria agreed with the user at intent level and recorded in the task
    files, so the first pick is the user's. Still open: who maps the agreed criteria to
    catalog names and cuts them to the depth's count (the process skill by a fixed
    table, or the main model through the `aspects` argument with the reason in one
    ledger line); may an aspect the user did not name ever run (proposal: `security`
    always runs when the change touches input handling, access or secrets, all others
    never); the default counts by depth (1, 2-3, 3-5); the slot of a split critic stage
    (opus slot, as proposed in 3.6, or main-model slot at `full`).
13. Scenario text form: one form for all processes (Gherkin or EARS), or chosen per
    process (EARS for requirements, Gherkin for scenarios, informal one-liners at
    `lite`)? Are scenario ids in test names acceptable in your repositories, so that
    coverage becomes a script check?
14. How much of the chain does `lite` keep: one short text with intent, requirements
    and scenario one-liners, confirmed by the user in chat? And is the user gate on the
    intent really wanted at every depth, or may `lite` start on the main session's own
    reading of the request and only show it?
15. Infrastructure changes: are control calls (GET requests, metrics, logs) written as
    a file of commands with expected results before the change, and run before and
    after it, the accepted form of "tests" for ops work?
