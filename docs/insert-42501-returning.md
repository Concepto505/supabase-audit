# `42501: new row violates row-level security policy` — when the `INSERT` policy is innocent

The error names your `INSERT`. You read the `WITH CHECK` expression twenty times.
It is correct. The same statement works in the SQL Editor with the same user's
claims. Through the API it fails every time.

The `INSERT` policy is not the problem. Your `SELECT` policy is.

## The mechanism

From the PostgreSQL documentation on
[`CREATE POLICY`](https://www.postgresql.org/docs/current/sql-createpolicy.html):

> If a data-modifying query has a `RETURNING` clause, `SELECT` permissions are
> required on the relation, and any newly inserted or updated rows from the
> relation must satisfy the relation's `SELECT` policies. If a newly inserted or
> updated row does not satisfy the relation's `SELECT` policies, an error will be
> thrown.

So an `INSERT ... RETURNING` is two permission checks, not one: `WITH CHECK` on
the way in, and the `SELECT` policy on the way back out. Fail either and you get a
row-level security error, and the two failures are hard to tell apart from the
message.

That is the whole asymmetry:

- **In the SQL Editor** you usually run a bare `insert into ... values (...)`. No
  `RETURNING`, so the `SELECT` policy is never consulted. It works.
- **Through PostgREST**, the row comes back — which is what `supabase-js` asks for
  the moment you chain `.select()`. The `SELECT` policy runs. It fails.

Same user, same claims, same policy definitions. Different statement.

## The thirty-second test

Do not audit policies yet. Remove the `RETURNING` and see what happens:

```js
// with .select()  → row is returned → SELECT policy is evaluated
const a = await supabase.from('documents').insert({ ... }).select()

// without        → nothing returned → SELECT policy never runs
const b = await supabase.from('documents').insert({ ... })
```

If `b` succeeds and `a` fails, the insert was always legal and you are looking at
the wrong policy. If both fail, it really is `WITH CHECK`.

This is worth doing first because the instinct on a `42501` is to stare at the
`INSERT` policy, and in this shape that is the one place the bug is not.

## The three shapes that cause it

**No `SELECT` policy at all.** RLS is on, you wrote an `INSERT` policy, and never
got round to the read side. Inserts that return the row fail unconditionally. This
is check 12 in [supabase-audit](https://github.com/Concepto505/supabase-audit).

**A `SELECT` policy the new row does not satisfy.** You can insert rows you are
not allowed to read — a row assigned to someone else, a draft that only becomes
visible once approved, a record whose `visible_at` is in the future. Perfectly
reasonable design, and every such insert fails as soon as it returns the row.

**A recursive or broken `SELECT` policy.** It was already failing on reads; the
insert is just where you finally noticed. See
[the recursion write-up](rls-infinite-recursion.md).

## The trap underneath the trap: `BEFORE INSERT` triggers

If a `BEFORE INSERT` trigger is what makes the row satisfy the `SELECT` policy —
it stamps `owner_id`, or inserts the membership row that the policy looks up —
you can hit an ordering problem where the policy is evaluated against a state the
trigger has not finished producing. Supabase has
[an open issue](https://github.com/supabase/supabase/issues/7289) describing
exactly this.

There is also a live PostgreSQL bug report,
[#19015](https://www.postgresql.org/message-id/19015-361c9035ff9d47d0%40postgresql.org),
for a narrower and nastier version: when the `SELECT` policy calls a function
marked `STABLE` and the insert has a `RETURNING` clause, the function can evaluate
against a snapshot that predates the trigger's change, and the server reports a
policy violation. The same insert without `RETURNING` succeeds, and so does the
same insert when the function is `VOLATILE`.

**This is a genuine tension with the usual performance advice.** Marking policy
helper functions `STABLE` is normally right — it is what stops them being
re-evaluated once per row. But if you have a `BEFORE INSERT` trigger whose effect
the policy depends on, and inserts with `RETURNING` fail while inserts without it
succeed, try `VOLATILE` on that specific helper before you rewrite your schema.
Slower, and correct, beats fast and rejected.

## What to actually do

Most of the time the fix is that the read side was never finished:

```sql
create policy documents_read on public.documents
for select to authenticated
using (owner_id = (select auth.uid()));
```

If the design genuinely is "you may create rows you cannot read", then stop asking
for the row back — insert without `.select()` and the conflict disappears, because
you are no longer asking Postgres to do something it is right to refuse.

---

Written by [David Borrás](https://nightfix-dev.netlify.app). Found via a thread on
the Supabase discussions where the reported cause and the real cause were two
different policies.
