# supabase-audit

One SQL file. Paste it into the Supabase SQL Editor, hit Run, get a list of the
things that are about to bite you — worst first.

No install, no npm package, no connection string handed to a stranger, no
account anywhere. It only `SELECT`s from system catalogs: it reads none of your
table data, writes nothing, and sends nothing anywhere. It is one file so that
you can read it before you run it.

```
curl -O https://raw.githubusercontent.com/Concepto505/supabase-audit/main/audit.sql
```

## What it checks

| # | Check | Why it matters |
|---|-------|----------------|
| 1 | Tables exposed to the API with **RLS disabled** | The anon key ships in your frontend bundle. Anyone can read every row. |
| 2 | **RLS on, zero policies** | Every client query returns an empty set. The classic "works in the SQL editor, returns nothing in the app". |
| 3 | Policies **open to `anon`** with an always-true condition | A leak, unless that data is deliberately public. |
| 4 | `SECURITY DEFINER` functions **executable by PUBLIC** | Postgres grants EXECUTE to PUBLIC by default. These are born open to the anon key. |
| 5 | `SECURITY DEFINER` **without a pinned `search_path`** | Privilege escalation: a caller can shadow a function it calls. |
| 6 | Views that **run as their owner** | RLS on the underlying tables is not applied to the caller. Often correct — flagged for a decision, not as a bug. |
| 7 | **Secret-shaped columns** on API-reachable tables | A leaked row hands over a live credential. |
| 8 | `auth.uid()` **re-evaluated per row** | The single biggest RLS slowdown. 20 ms vs 20 s on a large table. |
| 9 | Policies that **query their own table** | `infinite recursion detected in policy for relation`. |
| 10 | **Foreign keys with no index** | Every join and every cascading delete scans the whole table. |
| 11 | **Extensions installed in `public`** | Widens the API surface PostgREST exposes. |

## Two of these deserve a note

**#4 is the one that surprises people.** In Postgres, a newly created function
is executable by `PUBLIC` unless you say otherwise. On Supabase that means the
anon key can call it. The `REVOKE` has to live in the same migration that
creates the function, or there is a window where it is open.

**#6 is not automatically a bug.** A view without `security_invoker` runs with
its owner's rights, which is exactly right when the view already filters by
`auth.uid()` itself. Read the definition before you change it. Tools that flag
every such view as an issue are generating noise.

## Heuristics, stated plainly

Checks 9 and 10 are heuristics. #9 matches a policy expression that mentions its
own table name — confirm by reading the policy. #10 matches only the leading
index column, so an unusual composite index can produce a false positive. Both
are deliberately tuned to over-report rather than miss something.

Tested against Postgres 17 / Supabase. Requires Postgres 15+ for the
`security_invoker` check; everything else works on 12+.

## Licence

MIT. Take it, fork it, put it in your CI.

---

Built by [David Borrás](https://nightfix-dev.netlify.app), who fixes these for a
living when reading the list is not what you wanted to do tonight.
