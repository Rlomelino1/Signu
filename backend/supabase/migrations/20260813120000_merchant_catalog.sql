-- Migration #8 — MERCHANT_CATALOG
-- Source of truth: subscription-tracker-data-model.md (v38, 2026-08-13)
--
-- ADDITIVE ONLY. Creates one table and seeds it; touches nothing that exists.
--
-- WHY THIS EXISTS
--
-- The spec has referred to this table since v3 as "the future app-level table"
-- and two things have been waiting on it:
--
--   * R4 cannot fire without it. The engine ships R1, R2, R3 and R5; R4 —
--     "known subscription service, single charge" — is contract-only, which the
--     scope-limits section says out loud because a rule that silently never
--     fires reads as a rule that works.
--   * The logo chain has no input. v12 put the nullable `domain` here and
--     deliberately dropped `subscription.logo_url`, so this column is the only
--     source of a merchant domain anywhere in the system.
--
-- THIS TABLE IS REFERENCE DATA, NOT USER DATA
--
-- Every row is the same for every user: it describes the world, not an account.
-- That is why the RLS policy below reads `using (true)` rather than carrying a
-- `user_id` predicate — there is no user_id to carry, and inventing one would
-- make a shared fact look like a private one. It is also why the seed lives in a
-- migration rather than a seed script: `db reset` and production must agree, and
-- CI's "Schema applies" job then checks it on every PR.
--
-- WHY THE SEED IS DELIBERATELY NOT DERIVED FROM THE USER'S TRANSACTIONS
--
-- This is a privacy constraint, not a completeness one, and it is load-bearing.
--
-- The logo chain fetches by domain from a third party (logo.dev, v12). Fetching
-- only the domains a user is subscribed to would hand that third party the
-- user's subscription list, one request at a time. The client therefore fetches
-- EVERY domain in this catalog regardless of what the user has — a constant
-- request set that says nothing about anybody.
--
-- That padding only works if the catalog is independent of the user's data. A
-- catalog seeded from their own merchants would make "fetch everything" leak
-- precisely the list it was meant to hide. The same constraint serves R4: a
-- catalog built from services the user already has could only ever recognise
-- services the user already has, which is the opposite of catching a first
-- charge from a service they just signed up to.
--
-- So the seed below is a general list of well-known subscription services,
-- global and Brazilian, most of which any given user will not have.

create table public.merchant_catalog (
  id                uuid primary key default gen_random_uuid(),

  -- Canonical display name. What a confirmed subscription is called when the
  -- engine seeds `subscription.service_name` from a catalog hit.
  service_name      text not null,

  -- Nullable by design (v12): drives logo resolution, and a merchant with no
  -- known domain simply falls through to the monogram tile. Never a URL — a
  -- stored URL has no writer, no reader, and goes stale on rebrand, which is the
  -- failure the runtime-fetch tier order exists to avoid.
  domain            text,

  -- Seeds `subscription.category` on creation. User-editable afterwards; the
  -- engine never writes it again.
  category          text,

  -- R4's trigger: true iff a charge from this merchant is ALWAYS a subscription.
  -- Netflix is true; Amazon is false, because a marketplace charge is usually a
  -- purchase. Getting this wrong in the true direction manufactures suggestions
  -- out of one-off spending, so the default is stated per row rather than
  -- defaulted here — writer-states-everything.
  subscription_only boolean not null,

  -- Lowercase fragments matched against a transaction's normalised merchant.
  -- An array because one service arrives under several descriptors depending on
  -- the acquirer ("netflix", "netflix.com", "netflix br").
  patterns          text[] not null,

  created_at        timestamptz not null default now(),

  unique (service_name)
);

-- Pattern matching is a containment test over the array, which is what GIN is
-- for. Cheap to state now; adding it after the table has rows is a rewrite.
create index merchant_catalog_patterns_idx on public.merchant_catalog using gin (patterns);

alter table public.merchant_catalog enable row level security;

-- Shared reference data: every authenticated user reads every row. `using (true)`
-- is the honest expression of that, and the table holds nothing about anyone.
create policy "read the merchant catalog" on public.merchant_catalog
  for select using (true);

-- Cleared first, exactly as Migration #1 does for the other seven tables.
--
-- Not ceremony: a new table in `public` arrives carrying REFERENCES, TRIGGER and
-- TRUNCATE for `anon` and `authenticated` by default, and TRUNCATE is not a
-- privilege an unauthenticated role should hold over the catalog every client
-- reads. Verified against a real database rather than assumed — the seven
-- original tables show `anon` holding nothing at all, and without this line this
-- one showed `anon = REFERENCES, TRIGGER, TRUNCATE`. "A permission that arrives
-- by default is a permission that can leave by default" (Migration #3).
revoke all on public.merchant_catalog from anon, authenticated;

-- Stated explicitly rather than inherited. Migration #3 enumerated seven tables
-- by name and this is the eighth: a capability the design depends on has to be
-- written somewhere a migration can prove.
grant select on public.merchant_catalog to authenticated;
grant select, insert, update, delete on public.merchant_catalog to service_role;

-- `anon` gets nothing, matching Migration #1's posture.

-- ------------------------------------------------------------
-- Seed
--
-- Idempotent on `service_name`, so a re-run adds what is new and leaves the rest
-- alone. Domains are the brand's primary site — what logo.dev resolves against.
-- ------------------------------------------------------------

insert into public.merchant_catalog (service_name, domain, category, subscription_only, patterns) values
  -- Streaming — video
  ('Netflix',            'netflix.com',        'Streaming', true,  array['netflix']),
  ('Disney+',            'disneyplus.com',     'Streaming', true,  array['disney', 'disneyplus', 'disney plus']),
  ('Max',                'max.com',            'Streaming', true,  array['hbo', 'hbomax', 'max.com']),
  ('Prime Video',        'primevideo.com',     'Streaming', true,  array['prime video', 'primevideo']),
  ('Globoplay',          'globoplay.globo.com','Streaming', true,  array['globoplay', 'globo play']),
  ('Paramount+',         'paramountplus.com',  'Streaming', true,  array['paramount']),
  ('Apple TV+',          'tv.apple.com',       'Streaming', true,  array['apple tv']),
  ('Crunchyroll',        'crunchyroll.com',    'Streaming', true,  array['crunchyroll']),
  ('MUBI',               'mubi.com',           'Streaming', true,  array['mubi']),
  ('Telecine',           'telecine.com.br',    'Streaming', true,  array['telecine']),
  ('Looke',              'looke.com.br',       'Streaming', true,  array['looke']),
  ('YouTube Premium',    'youtube.com',        'Streaming', true,  array['youtube premium', 'youtubepremium', 'google youtube']),
  -- Streaming — audio
  ('Spotify',            'spotify.com',        'Music',     true,  array['spotify']),
  ('Deezer',             'deezer.com',         'Music',     true,  array['deezer']),
  ('Tidal',              'tidal.com',          'Music',     true,  array['tidal']),
  ('Apple Music',        'music.apple.com',    'Music',     true,  array['apple music']),
  ('Audible',            'audible.com',        'Books',     true,  array['audible']),
  ('Kindle Unlimited',   'amazon.com',         'Books',     true,  array['kindle unlimited', 'kindleunltd']),
  ('Storytel',           'storytel.com',       'Books',     true,  array['storytel']),
  -- Software and AI
  ('ChatGPT Plus',       'openai.com',         'AI',        true,  array['openai', 'chatgpt']),
  ('Claude',             'anthropic.com',      'AI',        true,  array['anthropic', 'claude.ai']),
  ('GitHub',             'github.com',         'Software',  false, array['github']),
  ('Notion',             'notion.so',          'Software',  true,  array['notion']),
  ('Figma',              'figma.com',          'Software',  true,  array['figma']),
  ('Canva',              'canva.com',          'Software',  true,  array['canva']),
  ('Adobe',              'adobe.com',          'Software',  true,  array['adobe']),
  ('Microsoft 365',      'microsoft.com',      'Software',  true,  array['microsoft 365', 'msft 365', 'office 365']),
  ('Google One',         'one.google.com',     'Storage',   true,  array['google one', 'googleone']),
  ('iCloud+',            'icloud.com',         'Storage',   true,  array['icloud']),
  ('Dropbox',            'dropbox.com',        'Storage',   true,  array['dropbox']),
  ('1Password',          '1password.com',      'Software',  true,  array['1password', 'agilebits']),
  ('Bitwarden',          'bitwarden.com',      'Software',  true,  array['bitwarden']),
  ('NordVPN',            'nordvpn.com',        'Software',  true,  array['nordvpn']),
  ('Grammarly',          'grammarly.com',      'Software',  true,  array['grammarly']),
  ('Todoist',            'todoist.com',        'Software',  true,  array['todoist']),
  ('Evernote',           'evernote.com',       'Software',  true,  array['evernote']),
  ('Zoom',               'zoom.us',            'Software',  true,  array['zoom.us', 'zoom video']),
  ('Slack',              'slack.com',          'Software',  true,  array['slack']),
  ('Linear',             'linear.app',         'Software',  true,  array['linear.app']),
  ('Vercel',             'vercel.com',         'Software',  true,  array['vercel']),
  ('Supabase',           'supabase.com',       'Software',  true,  array['supabase']),
  -- Gaming
  ('PlayStation Plus',   'playstation.com',    'Gaming',    true,  array['playstation', 'psn']),
  ('Xbox Game Pass',     'xbox.com',           'Gaming',    true,  array['xbox', 'game pass']),
  ('Nintendo Switch Online', 'nintendo.com',   'Gaming',    true,  array['nintendo']),
  ('Twitch',             'twitch.tv',          'Gaming',    false, array['twitch']),
  -- Delivery, transport, retail memberships
  ('iFood Clube',        'ifood.com.br',       'Food',      true,  array['ifood clube', 'ifood assinatura']),
  ('Rappi Prime',        'rappi.com.br',       'Food',      true,  array['rappi prime']),
  ('Uber One',           'uber.com',           'Transport', true,  array['uber one', 'uberone']),
  ('Meli+',              'mercadolivre.com.br','Shopping',  true,  array['meli+', 'meli mais', 'mercadolivre assinatura']),
  ('Amazon Prime',       'amazon.com.br',      'Shopping',  true,  array['amazon prime', 'prime br']),
  -- Health, fitness, learning
  ('Smart Fit',          'smartfit.com.br',    'Fitness',   true,  array['smart fit', 'smartfit']),
  ('Wellhub',            'wellhub.com',        'Fitness',   true,  array['wellhub', 'gympass']),
  ('Strava',             'strava.com',         'Fitness',   true,  array['strava']),
  ('Duolingo',           'duolingo.com',       'Learning',  true,  array['duolingo']),
  ('Coursera',           'coursera.org',       'Learning',  true,  array['coursera']),
  ('Alura',              'alura.com.br',       'Learning',  true,  array['alura']),
  -- Media and news
  ('Medium',             'medium.com',         'News',      true,  array['medium.com']),
  ('Substack',           'substack.com',       'News',      false, array['substack']),
  ('The New York Times', 'nytimes.com',        'News',      true,  array['nytimes', 'new york times']),
  ('Folha de S.Paulo',   'folha.uol.com.br',   'News',      true,  array['folha']),
  ('Estadão',            'estadao.com.br',     'News',      true,  array['estadao'])
on conflict (service_name) do nothing;
