# Your Edge Function CORS error is usually not a CORS problem

The browser says CORS. You add the `OPTIONS` handler everyone recommends. It still
says CORS. You add `Access-Control-Allow-Origin: *`. It still says CORS.

That is because "CORS error" in a browser console is not a diagnosis. It is what
the browser says whenever it refuses to let JavaScript read a response — including
when the response is a perfectly ordinary 401 or 500 that simply arrived without
the headers that would have let you see it.

There are three distinct failures behind it, and they need different fixes.

## 1. The preflight never reaches your code

This is the one that makes people angriest, because the fix everyone posts is
already in their function:

```ts
if (req.method === 'OPTIONS') {
  return new Response('ok', { headers: corsHeaders })
}
```

It does nothing, because **JWT verification is a platform gate that runs before
your function does**. A browser preflight is an `OPTIONS` request sent *without*
the `Authorization` header — that is required behaviour, preflights never carry
credentials. So the platform sees an unauthenticated request, returns 401, and
your handler is never invoked
([Supabase: unable to call Edge Function](https://supabase.com/docs/guides/troubleshooting/unable-to-call-edge-function)).

The fix is not in your code. Turn off JWT verification for that function —
Dashboard → Edge Functions → *your function* → Settings → JWT Verification, or
`verify_jwt = false` in config — **and then check the JWT yourself inside the
function**, after you have answered the preflight:

```ts
if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(req) })

const token = req.headers.get('Authorization')?.replace('Bearer ', '')
if (!token) return json({ error: 'unauthorized' }, 401, req)
// verify it, then carry on
```

Turning the gate off does not make the function public unless you then forget the
second half. Write both halves in the same commit.

## 2. Your successful response has the headers and your error response does not

Nearly every example puts `corsHeaders` on the happy path and on the `OPTIONS`
branch, and nowhere else. Then the function throws, the runtime returns a bare
500, and the browser — unable to read a response with no CORS headers — reports a
CORS error.

So you spend an hour on CORS while the actual bug is an undefined variable on
line 40.

Put the headers on every exit, including the ones you did not write:

```ts
try {
  // ...
  return json(result, 200, req)
} catch (err) {
  console.error(err)                       // this is the thing you actually want
  return json({ error: String(err) }, 500, req)
}
```

**If a function ever worked and now returns "CORS error" after a code change, it
is almost certainly throwing.** Check the function logs before touching a single
header.

## 3. The header allowlist does not match what the browser asked for

A preflight announces what the real request intends to send, in
`Access-Control-Request-Headers`. If your `Access-Control-Allow-Headers` does not
cover every one of them, the preflight fails — and `supabase-js` sends more than
people expect: `authorization`, `apikey`, `x-client-info`, `content-type`, plus
anything you added yourself.

Hardcoding that list is how this breaks six months later when a client library
adds a header. Echo back what was asked for instead:

```ts
const cors = (req: Request) => ({
  'Access-Control-Allow-Origin': req.headers.get('Origin') ?? '*',
  'Access-Control-Allow-Headers':
    req.headers.get('Access-Control-Request-Headers') ?? 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
  'Vary': 'Origin',
})
```

Two notes on that. `Vary: Origin` matters the moment a CDN is in front of you, or
one origin's response gets cached and served to another. And if you need
`credentials: 'include'`, `Access-Control-Allow-Origin` **cannot** be `*` — it has
to be the actual origin, which is what echoing gives you.

Echoing the origin is not an allowlist. If you need one, check the origin against
your list and refuse early — but do it explicitly, rather than by accident through
a stale hardcoded string.

For newer projects, `@supabase/supabase-js` v2.95+ exports ready-made headers via
`npm:@supabase/supabase-js@^2/cors`, which is worth using instead of a copied
snippet that drifts.

## Telling them apart in thirty seconds

`curl` does not enforce CORS, so it shows you what the server actually said:

```bash
curl -i -X OPTIONS 'https://<ref>.supabase.co/functions/v1/<fn>' \
  -H 'Origin: http://localhost:3000' \
  -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: authorization, content-type'
```

| What you see | What it is |
|---|---|
| `401` | Failure 1 — JWT verification, before your code |
| `200` with no `Access-Control-Allow-*` headers | Your `OPTIONS` branch is not returning them |
| `200` with correct headers, but the real POST still fails | Failure 2 — the POST is erroring, and the error has no CORS headers |

Then repeat with the real method:

```bash
curl -i -X POST 'https://<ref>.supabase.co/functions/v1/<fn>' \
  -H 'Authorization: Bearer <token>' -H 'Content-Type: application/json' -d '{}'
```

If that returns a 500, your CORS configuration was never the problem.

---

Written by [David Borrás](https://nightfix-dev.netlify.app). If the logs are empty
and the console still says CORS, that is the sort of thing I untangle.
