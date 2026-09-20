# `infinite recursion detected in policy for relation`

You added a policy, the table stopped answering, and Postgres is telling you it
gave up. The message is precise and the fix is small, but almost every first
attempt at it makes the problem worse. Here is what is actually happening.

## The shape that causes it

You have a members table and you want people to see their organisation's rows:

```sql
create policy members_read on public.organization_members
for select to authenticated
using (
  organization_id in (
    select organization_id from public.organization_members
    where user_id = auth.uid()          -- ← reads the table it is protecting
  )
);
```

To decide whether you may read a row of `organization_members`, Postgres has to
run the policy. The policy reads `organization_members`. To read
`organization_members`, Postgres has to run the policy. It detects the loop and
raises rather than hanging.

**It does not have to be this obvious.** The same loop appears when the policy on
table A queries table B, and the policy on table B queries table A. Postgres
reports it against whichever relation it noticed first, which is why the table
named in the error is sometimes not the table you need to change.

## The three fixes that do not work

**Disabling RLS on the membership table.** It stops the error by removing the
security boundary — the anon key ships in your frontend bundle, so this publishes
your entire tenancy map.

**Adding `TO authenticated`.** The role gate decides whether the policy applies,
not what the policy costs. The recursion is in the expression.

**Rewriting `in (...)` as `exists (...)`.** Cosmetic. The subquery still touches
the protected table.

## The fix that works

Move the lookup into a `SECURITY DEFINER` function. Such a function runs with its
owner's privileges, and **RLS is not applied to the owner's own access** — so the
lookup inside it does not re-trigger the policy, and the loop is broken:

```sql
create or replace function public.current_org_ids()
returns setof uuid
language sql
stable                      -- evaluated once per statement, not once per row
security definer
set search_path = ''        -- pin it: see below
as $$
  select m.organization_id
  from public.organization_members m
  where m.user_id = (select auth.uid())
$$;

revoke execute on function public.current_org_ids() from public;
grant  execute on function public.current_org_ids() to authenticated;
```

Then the policy on every tenant-owned table becomes non-recursive:

```sql
create policy documents_read on public.documents
for select to authenticated
using (organization_id in (select public.current_org_ids()));
```

And the membership table itself gets a policy that is **self-contained** — this is
the base case, and it is the part people forget:

```sql
create policy members_read_own on public.organization_members
for select to authenticated
using (user_id = (select auth.uid()));
```

A user sees their own membership rows directly, with no subquery. Everything else
goes through the function. No cycle exists anywhere.

## Four details that decide whether this is safe or a hole

**`revoke execute ... from public` is not optional.** In Postgres a newly created
function is executable by `PUBLIC` by default. On Supabase that means the anon key
can call it the instant it exists. The `REVOKE` has to be in the *same migration*
as the `CREATE`, or there is a window — on a hosted project, a window open to the
internet — where anyone can call it. This is the single most common way a
correctly-reasoned definer function turns into a hole.

**`set search_path = ''` is not optional either.** A `SECURITY DEFINER` function
with a mutable search path can be induced to call a shadowed object while running
as its owner. Pin the path and schema-qualify every reference inside the body, as
above.

**Mark it `STABLE`.** Without it the planner treats the function as `VOLATILE` and
may call it once per row. On a table with a few hundred thousand rows that is the
difference between milliseconds and half a minute.

**Check whether the table has `FORCE ROW LEVEL SECURITY`.** The whole technique
rests on table owners being exempt from RLS. That exemption disappears if someone
ran `alter table ... force row level security`, which subjects the owner to the
policies too — and then the definer function recurses exactly like the policy did.
If you have forced RLS deliberately, the lookup has to live in a table that has
not, or in a role with `BYPASSRLS`.

**Return the narrowest thing you can.** `current_org_ids()` returns ids, not rows.
A helper that returns whole membership rows is an oracle: anyone permitted to call
it can read the tenancy map, which is what you were protecting.

## Why `(select auth.uid())` and not `auth.uid()`

Wrapped in a subquery, the call becomes an InitPlan that Postgres evaluates once
per statement. Written bare, it is evaluated per row. Both are correct; only one
is usable on a large table. This is worth doing everywhere in policies, not only
here.

## Finding every instance of it

The recursion only announces itself on the query path that hits it, so a policy
written months ago can sit quietly until a particular filter finally reaches it.
Check 9 of [supabase-audit](https://github.com/Concepto505/supabase-audit) flags
policies whose expression references their own table — one SQL file you paste into
the SQL Editor, no install, no credentials shared. It over-reports on purpose:
confirm each hit by reading the policy.

---

Written by [David Borrás](https://nightfix-dev.netlify.app). If you would rather
have this fixed than read about it, that is what I do.
