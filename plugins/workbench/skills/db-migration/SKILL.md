---
name: db-migration
description: Creates and validates a database migration — autogen, local upgrade/downgrade test, doc update. Canonical example of a stack-specific skill.
disable-model-invocation: true
---

# /workbench:db-migration

> EXAMPLE skill, to be adapted to the project's ORM via /core:new-project (Alembic,
> Prisma, Drizzle, golang-migrate…). The skeleton below is the invariant.

1. **Pre-flight**: current schema vs models — confirm the expected delta with
   the user before generating.
2. **Autogen**: generate the migration with the project's tool; RE-READ the
   generated script (autogens miss renames and constraints).
3. **Local test**: apply (upgrade) on a local/disposable database, verify
   the schema, then **downgrade** and verify the return to the initial state.
   A migration without a tested downgrade is not shippable.
4. **Doc**: update docs/STACK.md (impacted schema/services). If the
   migration changes the structure in a long-term way (new store, partition,
   table removal) → ADR draft via the architect agent.

Guardrails: never on a shared/staging/prod database; never real data
in fixtures; DATABASE_URL comes from the env, never hardcoded.
