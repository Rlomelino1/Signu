import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { verificationKey, writeKey } from './auth.ts'

const ANON = 'eyJhbGciOiJIUzI1NiJ9.anon.signature'
const PUB = 'sb_publishable_EXAMPLEEXAMPLEEXAMPLE'

Deno.test('a publishable key is preferred over the legacy anon key', () => {
  const v = verificationKey({ SUPABASE_ANON_KEY: ANON, SUPABASE_PUBLISHABLE_KEYS: PUB })
  assertEquals(v, { key: PUB, source: 'publishable' })
})

Deno.test('the anon key is the fallback, so behaviour is unchanged where no publishable key is injected', () => {
  const v = verificationKey({ SUPABASE_ANON_KEY: ANON, SUPABASE_PUBLISHABLE_KEYS: '' })
  assertEquals(v, { key: ANON, source: 'anon' })
})

Deno.test('the injected shape is undocumented, so every plausible one is accepted', () => {
  const shapes = [
    PUB,
    ` ${PUB} `,
    `${PUB},sb_secret_NEVERUSETHIS`,
    `sb_secret_NEVERUSETHIS ${PUB}`,
    JSON.stringify([PUB]),
    JSON.stringify([{ name: 'default', api_key: PUB }]),
    JSON.stringify({ default: PUB }),
  ]
  for (const raw of shapes) {
    const v = verificationKey({ SUPABASE_ANON_KEY: ANON, SUPABASE_PUBLISHABLE_KEYS: raw })
    assertEquals(v.key, PUB, `shape not handled: ${raw}`)
    assertEquals(v.source, 'publishable')
  }
})

Deno.test('a secret key is never selected, whatever the shape', () => {
  const v = verificationKey({
    SUPABASE_ANON_KEY: ANON,
    SUPABASE_PUBLISHABLE_KEYS: JSON.stringify([{ api_key: 'sb_secret_NEVERUSETHIS' }]),
  })
  assertEquals(v, { key: ANON, source: 'anon' })
})

Deno.test('a container shape that is malformed, or simply new, still yields the key', () => {
  for (const raw of [`[${PUB}`, `{"keys":[{"k":"${PUB}"}]}`, `key=${PUB};`, `<${PUB}>`]) {
    assertEquals(verificationKey({ SUPABASE_ANON_KEY: ANON, SUPABASE_PUBLISHABLE_KEYS: raw }).key, PUB)
  }
})

Deno.test('nothing injected is reported rather than guessed', () => {
  assertEquals(verificationKey({}), { key: '', source: 'none' })
})

const SERVICE = 'eyJhbGciOiJIUzI1NiJ9.service_role.signature'
const SECRET = 'sb_secret_EXAMPLEEXAMPLEEXAMPLE'

Deno.test('a secret key is preferred over the legacy service_role key', () => {
  const v = writeKey({ SUPABASE_SERVICE_ROLE_KEY: SERVICE, SUPABASE_SECRET_KEYS: SECRET })
  assertEquals(v, { key: SECRET, source: 'secret' })
})

Deno.test('the service_role key is the fallback, so behaviour is unchanged today', () => {
  const v = writeKey({ SUPABASE_SERVICE_ROLE_KEY: SERVICE, SUPABASE_SECRET_KEYS: '' })
  assertEquals(v, { key: SERVICE, source: 'service_role' })
})

Deno.test('THE SAFETY PROPERTY: a publishable key is never used to write', () => {
  const v = writeKey({ SUPABASE_SERVICE_ROLE_KEY: SERVICE, SUPABASE_SECRET_KEYS: PUB })
  assertEquals(v, { key: SERVICE, source: 'service_role' })
})

Deno.test('and the reverse: a secret key is never used to verify a caller', () => {
  const v = verificationKey({ SUPABASE_ANON_KEY: ANON, SUPABASE_PUBLISHABLE_KEYS: SECRET })
  assertEquals(v, { key: ANON, source: 'anon' })
})

Deno.test('the write key survives any container shape, like the verification key', () => {
  for (const raw of [SECRET, ` ${SECRET} `, JSON.stringify([{ api_key: SECRET }]), `[${SECRET}`]) {
    assertEquals(writeKey({ SUPABASE_SERVICE_ROLE_KEY: SERVICE, SUPABASE_SECRET_KEYS: raw }).key, SECRET)
  }
})

Deno.test('nothing injected for writes is reported rather than guessed', () => {
  assertEquals(writeKey({}), { key: '', source: 'none' })
})
