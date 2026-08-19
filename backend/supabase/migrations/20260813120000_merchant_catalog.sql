
create table public.merchant_catalog (
  id                uuid primary key default gen_random_uuid(),

  service_name      text not null,

  domain            text,

  category          text,

  subscription_only boolean not null,

  patterns          text[] not null,

  created_at        timestamptz not null default now(),

  unique (service_name)
);

create index merchant_catalog_patterns_idx on public.merchant_catalog using gin (patterns);

alter table public.merchant_catalog enable row level security;

create policy "read the merchant catalog" on public.merchant_catalog
  for select using (true);

revoke all on public.merchant_catalog from anon, authenticated;

grant select on public.merchant_catalog to authenticated;
grant select, insert, update, delete on public.merchant_catalog to service_role;



insert into public.merchant_catalog (service_name, domain, category, subscription_only, patterns) values
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
  ('Spotify',            'spotify.com',        'Music',     true,  array['spotify']),
  ('Deezer',             'deezer.com',         'Music',     true,  array['deezer']),
  ('Tidal',              'tidal.com',          'Music',     true,  array['tidal']),
  ('Apple Music',        'music.apple.com',    'Music',     true,  array['apple music']),
  ('Audible',            'audible.com',        'Books',     true,  array['audible']),
  ('Kindle Unlimited',   'amazon.com',         'Books',     true,  array['kindle unlimited', 'kindleunltd']),
  ('Storytel',           'storytel.com',       'Books',     true,  array['storytel']),
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
  ('PlayStation Plus',   'playstation.com',    'Gaming',    true,  array['playstation', 'psn']),
  ('Xbox Game Pass',     'xbox.com',           'Gaming',    true,  array['xbox', 'game pass']),
  ('Nintendo Switch Online', 'nintendo.com',   'Gaming',    true,  array['nintendo']),
  ('Twitch',             'twitch.tv',          'Gaming',    false, array['twitch']),
  ('iFood Clube',        'ifood.com.br',       'Food',      true,  array['ifood clube', 'ifood assinatura']),
  ('Rappi Prime',        'rappi.com.br',       'Food',      true,  array['rappi prime']),
  ('Uber One',           'uber.com',           'Transport', true,  array['uber one', 'uberone']),
  ('Meli+',              'mercadolivre.com.br','Shopping',  true,  array['meli+', 'meli mais', 'mercadolivre assinatura']),
  ('Amazon Prime',       'amazon.com.br',      'Shopping',  true,  array['amazon prime', 'prime br']),
  ('Smart Fit',          'smartfit.com.br',    'Fitness',   true,  array['smart fit', 'smartfit']),
  ('Wellhub',            'wellhub.com',        'Fitness',   true,  array['wellhub', 'gympass']),
  ('Strava',             'strava.com',         'Fitness',   true,  array['strava']),
  ('Duolingo',           'duolingo.com',       'Learning',  true,  array['duolingo']),
  ('Coursera',           'coursera.org',       'Learning',  true,  array['coursera']),
  ('Alura',              'alura.com.br',       'Learning',  true,  array['alura']),
  ('Medium',             'medium.com',         'News',      true,  array['medium.com']),
  ('Substack',           'substack.com',       'News',      false, array['substack']),
  ('The New York Times', 'nytimes.com',        'News',      true,  array['nytimes', 'new york times']),
  ('Folha de S.Paulo',   'folha.uol.com.br',   'News',      true,  array['folha']),
  ('Estadão',            'estadao.com.br',     'News',      true,  array['estadao'])
on conflict (service_name) do nothing;
