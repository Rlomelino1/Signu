import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { verificationKey } from './auth.ts'

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
