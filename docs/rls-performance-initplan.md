# The RLS mistake that costs you 10,000x and never throws an error

This one does not break. That is what makes it expensive. The policy is correct,
the rows returned are right, the tests pass. The table is just slow, and it gets
slower as the data grows, and nothing in the logs says why.

```sql
-- the slow version
using (user_id = auth.uid())

-- the fast version
using (user_id = (select auth.uid()))
```

That is the entire change.

## Why two characters matter

A policy expression is evaluated **once per row considered**. Written bare,
`auth.uid()` is a function call inside that per-row expression, so scanning
100,000 rows means 100,000 calls.

Wrapped in a subquery, the planner recognises an expression that does not depend
on the current row, pulls it into an **InitPlan**, and runs it exactly once at the
start of the query. Every row check then compares against a literal value — which
also gives the planner something an index can be used against, instead of a
function call it has to evaluate before it can compare anything.

## The numbers, from Supabase's own benchmarks

On a 100,000-row table
([RLS performance and best practices](https://supabase.com/docs/guides/troubleshooting/rls-performance-and-best-practices-Z5Jjwv)):

| Policy | Bare | Wrapped in `(select ...)` |
|---|---|---|
| `auth.uid() = user_id` | 179 ms | **9 ms** |
| a `SECURITY DEFINER` role check | 178 **seconds** | **12 ms** |

The second row is the one to look at. It is not a 20x tidy-up, it is roughly
14,000x, and it is the shape most multi-tenant apps end up with — because the
recommended way to avoid policy recursion is precisely to call a `SECURITY
DEFINER` helper from the policy. Do that without wrapping it and you have traded
a loud error for a silent catastrophe.

## It applies to more than `auth.uid()`

Anything the row does not influence belongs in an InitPlan: `auth.jwt()`,
`auth.role()`, `current_setting(...)`, and above all your own helper functions:

```sql
using (organization_id in (select public.current_org_ids()))
```

That form is already wrapped — the subquery is the InitPlan. Written as
`organization_id = any(public.current_org_ids())` with a bare call, it is not.

**The wrapping only helps when the expression is genuinely row-independent.** If
the subquery references the outer row it becomes a correlated subquery, no
InitPlan is created, and you are back to per-row evaluation with extra syntax.

## Two neighbours worth fixing in the same migration

**Index the column the policy filters on.** The policy predicate runs on every
query against that table, so it is the hottest comparison in your schema. An
unindexed `organization_id` or `user_id` means the fast path still ends in a
sequential scan.

**Do not stack permissive policies.** Permissive policies are OR'd, and *each one*
is evaluated per row. Four permissive `SELECT` policies on a table is four
expressions per row. Consolidating them into one with an `OR` inside is usually
both clearer and cheaper.

Also give every policy a `TO` clause. A policy with no role gate is considered for
every role, including requests that could never have matched it.

## Finding them

Supabase's dashboard has a performance lint for exactly this,
[`auth_rls_initplan`](https://supabase.com/docs/guides/database/database-advisors?lint=0003_auth_rls_initplan),
and it also flags multiple permissive policies and unindexed foreign keys.

If you would rather have it in one file you can read, diff and run in CI,
check 8 of [supabase-audit](https://github.com/Concepto505/supabase-audit) flags
unwrapped `auth.*()` calls in policies and check 10 flags foreign keys with no
supporting index.

## Fixing it is mechanical, and that is the risk

The migration is a drop-and-recreate of every flagged policy with `(select ...)`
inserted. It touches security-critical code for a performance reason, which is
exactly the situation where a typo becomes a data leak rather than a slow query.

Change the wrapping and nothing else. Then re-read each policy's predicate and
confirm it says the same thing it said before. A rewrite that is 14,000x faster
and returns one extra row is not an improvement.

---

Written by [David Borrás](https://nightfix-dev.netlify.app). Rewriting a schema's
worth of policies without changing what any of them mean is the sort of thing I do.
