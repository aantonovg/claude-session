Aspect: data integrity. Read the object for the places where data can be lost, silently changed or contradicted: a write that is not atomic, a file two writers share, a record updated without the check that it is the one meant, a conversion that drops a field, a default that overwrites a value somebody set.

Typical shapes: read-modify-write with no guard against a second writer; a partial result left on disk when a step dies; an identifier reused after a rename; a migration with no way back; two stores holding the same fact with no check that they agree; truncation, encoding or rounding that nobody notices.

Out of scope: schema taste, storage choice, and durability guarantees the object's stated constraints hand to another component. A hint names the record, the moment it can be damaged, and how one would see it afterwards.
