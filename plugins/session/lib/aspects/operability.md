Aspect: operability. Read the object as the person who has to run it, watch it and repair it at the worst moment: can they tell what happened, where it stopped, what to do next, and can they undo it?

Typical shapes: a failure with no message naming the input that caused it; a run that leaves no record of what it did; a state file nobody can read by hand; a step that is not safe to run twice; no way to resume after a death in the middle; a message that names an internal symbol instead of the action that failed; an irreversible step with no confirmation and no backup.

Out of scope: monitoring stacks, dashboards and alerting policy, and operations the object's stated scope hands to somebody else. A hint names the moment of trouble and what the operator would be missing then.
