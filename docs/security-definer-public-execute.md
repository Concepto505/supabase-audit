# Every function you create is callable by `anon`, until you say otherwise

This is not a Supabase quirk. It is PostgreSQL's default, it is documented, and it
surprises nearly everyone the first time:

> PostgreSQL grants privileges on some types of objects to `PUBLIC` by default when
> the objects are created. [...] `EXECUTE` privilege for functions and procedures.
> — [Privileges, §5.8](https://www.postgresql.org/docs/current/ddl-priv.html)

Tables are not like this. Create a table and nobody can touch it until you grant
something. Create a *function* and everyone can run it immediately.

On a hosted Supabase project, "everyone" has a specific meaning. The `anon` key is
in your frontend bundle, every function in an exposed schema is reachable as
`POST /rest/v1/rpc/<name>`, and `PUBLIC` includes `anon`. So the moment the
migration commits, your function is an internet endpoint.

## Why `SECURITY DEFINER` turns this from untidy into serious

An ordinary function runs with the caller's privileges. If `anon` calls it, RLS
still applies, the caller still cannot read what they could not read anyway. The
blast radius is small.

A `SECURITY DEFINER` function runs with its **owner's** privileges, and table
owners are exempt from RLS. That is the entire point of it — it is how you break
policy recursion and how you do controlled privilege elevation. It also means an
unrevoked `SECURITY DEFINER` function is a hole straight through every policy you
wrote.

The functions most likely to be `SECURITY DEFINER` are exactly the ones you least
want exposed: `current_org_ids()`, `is_admin()`, `promote_user()`,
`get_user_by_email()`. A helper that returns the caller's organisation ids is
harmless when only the policy calls it, and is a tenancy map when `anon` can call
it directly.

## The window, and why it is not theoretical

```sql
-- migration 042
create function public.current_org_ids() ...;   -- ← callable by anon from here
revoke execute on function public.current_org_ids() from public;
```

Inside one migration those two statements are in the same transaction, and the
window closes before anything is visible. Split across two migrations, the window
is however long it takes you to deploy the second one — and if the second one is
never written because the first one "worked", the window is permanent.

**Put the `REVOKE` in the same migration as the `CREATE`. Every time.**

## The trap that reopens a function you already closed

`CREATE OR REPLACE FUNCTION` preserves the existing privileges. `DROP FUNCTION`
followed by `CREATE FUNCTION` does not — the new function is a new object and gets
the default ACL, which is open to `PUBLIC`.

So a migration that changes a function's signature, and therefore has to drop and
recreate it, silently undoes a `REVOKE` you did six months ago. Nothing in the
diff looks like a permissions change. This is the most common way a project that
got this right regresses.

If a migration drops a function, it re-revokes it. No exceptions.

## Fixing it for everything you create from now on

You can change the default rather than remembering the `REVOKE` each time:

```sql
alter default privileges for role postgres
  revoke execute on functions from public;
```

Two details that decide whether this works:

**It only affects objects created by the role you name.** Default privileges are
per-creating-role. On Supabase, migrations run as `postgres`, so that is the role
to name — but a function created by any other role is unaffected.

**Do not add `IN SCHEMA`.** Per-schema default privileges can only *add* to the
global setting, never remove what the global default granted, so
`alter default privileges in schema public revoke execute on functions from public`
does nothing at all while appearing to work. The command must be written without
the schema clause ([ALTER DEFAULT PRIVILEGES](https://www.postgresql.org/docs/17/sql-alterdefaultprivileges.html)).

And it is not retroactive. It changes what happens next; it does not close
anything already open.

## Before you revoke everything, know what you are breaking

Blanket-revoking `EXECUTE` from `PUBLIC` across a live database can break things
that quietly depended on it — extension functions, helpers called by other
functions running as a role you did not think about, anything in your app that
calls an RPC as `anon` on purpose (a public signup check, a rate-limited lookup).

Work from the list, not from a broom. Revoke, then grant back explicitly to the
role that should have it:

```sql
revoke execute on function public.current_org_ids() from public;
grant  execute on function public.current_org_ids() to authenticated;
```

Explicit grants are also self-documenting: six months later, `\df+` tells the next
person who was supposed to be able to call this.

## Finding the ones already open

Check 4 of [supabase-audit](https://github.com/Concepto505/supabase-audit) lists
every `SECURITY DEFINER` function that still has `EXECUTE` granted to `PUBLIC`, and
check 5 lists those without a pinned `search_path`, which is the other half of the
same problem. One SQL file, pasted into the SQL Editor, reading only system
catalogs.

---

Written by [David Borrás](https://nightfix-dev.netlify.app). If the list comes back
longer than you hoped, that is the sort of thing I fix.
