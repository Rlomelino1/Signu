import {
  assertEquals,
  assertNotMatch,
  assertRejects,
  assertStringIncludes,
} from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { pluggy, pluggyApiKey, PluggyError } from './pluggy.ts'

interface Recorded {
  url: string
  method?: string
  headers: Record<string, string>
  body?: string
}

function stubFetch(reply: (call: Recorded) => Response) {
  const original = globalThis.fetch
  const calls: Recorded[] = []
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    const headers: Record<string, string> = {}
    new Headers(init?.headers).forEach((value, key) => {
      headers[key] = value
    })
    const call: Recorded = {
      url: String(input),
      method: init?.method,
      headers,
      body: typeof init?.body === 'string' ? init.body : undefined,
    }
    calls.push(call)
    return Promise.resolve(reply(call))
  }) as typeof globalThis.fetch
  return { calls, restore: () => { globalThis.fetch = original } }
}

function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { 'content-type': 'application/json' },
  })
}

Deno.test('a request goes to the Pluggy host at the given path and parses the body', async () => {
  const f = stubFetch(() => json({ results: [{ id: 'item-1' }] }))
  try {
    const out = await pluggy<{ results: { id: string }[] }>('/items/item-1', 'key-1')
    assertEquals(out.results[0].id, 'item-1')
    assertEquals(f.calls[0].url, 'https://api.pluggy.ai/items/item-1')
  } finally {
    f.restore()
  }
})

Deno.test('an api key is sent as X-API-KEY, and omitted entirely when there is none', async () => {
  const f = stubFetch(() => json({}))
  try {
    await pluggy('/items', 'key-1')
    assertEquals(f.calls[0].headers['x-api-key'], 'key-1')
    assertEquals(f.calls[0].headers['content-type'], 'application/json')

    await pluggy('/auth', null)
    assertEquals('x-api-key' in f.calls[1].headers, false, 'a null key must not send the header at all')
  } finally {
    f.restore()
  }
})

Deno.test('caller headers win, so a caller can override the default content type', async () => {
  const f = stubFetch(() => json({}))
  try {
    await pluggy('/items', 'key-1', { headers: { 'Content-Type': 'text/plain' } })
    assertEquals(f.calls[0].headers['content-type'], 'text/plain')
    assertEquals(f.calls[0].headers['x-api-key'], 'key-1')
  } finally {
    f.restore()
  }
})

Deno.test('every upstream failure surfaces as 502, naming the method, path and upstream status', async () => {
  const f = stubFetch(() => new Response('not found', { status: 404 }))
  try {
    const error = await assertRejects(() => pluggy('/items/missing', 'key-1'), PluggyError)
    assertEquals(error.status, 502, 'the caller reports a bad gateway, not the upstream status')
    assertStringIncludes(error.message, 'GET')
    assertStringIncludes(error.message, '/items/missing')
    assertStringIncludes(error.message, '404')
    assertStringIncludes(error.message, 'not found')
  } finally {
    f.restore()
  }
})

Deno.test('the method named in the failure is the one that was sent', async () => {
  const f = stubFetch(() => new Response('nope', { status: 500 }))
  try {
    const error = await assertRejects(
      () => pluggy('/items', 'key-1', { method: 'DELETE' }),
      PluggyError,
    )
    assertStringIncludes(error.message, 'DELETE /items')
  } finally {
    f.restore()
  }
})

Deno.test('an enormous upstream body is truncated, so one bad response cannot flood the log', async () => {
  const f = stubFetch(() => new Response('x'.repeat(5000), { status: 503 }))
  try {
    const error = await assertRejects(() => pluggy('/items', 'key-1'), PluggyError)
    assertEquals(error.message.includes('x'.repeat(400)), true)
    assertEquals(error.message.includes('x'.repeat(401)), false, 'the body is capped at 400 characters')
  } finally {
    f.restore()
  }
})

Deno.test('missing credentials fail before any request is made', async () => {
  const f = stubFetch(() => json({ apiKey: 'should-never-be-reached' }))
  try {
    for (const creds of [
      {},
      { clientId: 'id-only' },
      { clientSecret: 'secret-only' },
      { clientId: '', clientSecret: 'secret' },
    ]) {
      const error = await assertRejects(() => pluggyApiKey(creds), PluggyError)
      assertEquals(error.status, 500, 'unconfigured is our fault, not the upstream gateway')
      assertStringIncludes(error.message, 'PLUGGY_CLIENT_ID')
    }
    assertEquals(f.calls.length, 0, 'credentials are checked before the network is touched')
  } finally {
    f.restore()
  }
})

Deno.test('credentials are exchanged at /auth by POST, unauthenticated, and the key returned', async () => {
  const f = stubFetch(() => json({ apiKey: 'fresh-key' }))
  try {
    const key = await pluggyApiKey({ clientId: 'id-1', clientSecret: 'secret-1' })
    assertEquals(key, 'fresh-key')
    assertEquals(f.calls.length, 1)
    assertEquals(f.calls[0].url, 'https://api.pluggy.ai/auth')
    assertEquals(f.calls[0].method, 'POST')
    assertEquals('x-api-key' in f.calls[0].headers, false, 'the exchange is what obtains the key')
    assertEquals(JSON.parse(f.calls[0].body ?? '{}'), { clientId: 'id-1', clientSecret: 'secret-1' })
  } finally {
    f.restore()
  }
})

Deno.test('an auth response without an apiKey is a gateway failure, not an empty key', async () => {
  for (const body of [{}, { apiKey: '' }, { apiKey: null }]) {
    const f = stubFetch(() => json(body))
    try {
      const error = await assertRejects(
        () => pluggyApiKey({ clientId: 'id-1', clientSecret: 'secret-1' }),
        PluggyError,
      )
      assertEquals(error.status, 502)
      assertStringIncludes(error.message, 'no apiKey')
    } finally {
      f.restore()
    }
  }
})

Deno.test('a rejected exchange never puts the client secret in the error', async () => {
  const secret = 'super-secret-value-9f3a'
  const f = stubFetch((call) => new Response(`invalid credentials for ${call.body}`, { status: 401 }))
  try {
    const error = await assertRejects(
      () => pluggyApiKey({ clientId: 'id-1', clientSecret: secret }),
      PluggyError,
    )
    assertNotMatch(
      error.message,
      new RegExp(secret),
      'the upstream echoed the request body, and this message is logged',
    )
    assertStringIncludes(error.message, '401')
    assertStringIncludes(error.message, 'withheld')
    assertEquals(error.upstreamStatus, 401, 'the diagnostic survives even though the body does not')
  } finally {
    f.restore()
  }
})
