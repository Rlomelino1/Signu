-- Migration #11 — the profile picture, and the name it sits beside
-- Source of truth: subscription-tracker-data-model.md (v47, 2026-08-14)
--
-- ADDITIVE ONLY: one nullable column, one column-scoped grant, one storage
-- bucket, four storage policies. No existing column, constraint, index, policy or
-- grant is altered, and nothing the engine owns is touched.
--
-- WHY A COLUMN AT ALL, WHEN THE PATH COULD BE DERIVED
--
-- `<uid>/avatar.jpg` would need no column: the client could ask storage and treat
-- a 404 as "no picture". Rejected for two reasons, one of them a bug waiting to
-- happen. First, it makes "has a picture" a network round trip on every launch,
-- for the common case of not having one. Second, a FIXED path cannot be cached:
-- overwriting it leaves every cached copy stale with no way to notice, which is
-- exactly the trap `LogoStore` avoided in v38 by keying its TTL on the file's own
-- mtime rather than a header.
--
-- So the column stores the path and every upload writes a NEW one
-- (`<uid>/<epoch>.jpg`). The path IS the cache key: a changed picture is a changed
-- path, a stale cache entry is impossible by construction, and `GraphSignature`
-- already notices a changed profile row, so the app refreshes without new
-- plumbing.
--
-- WHY THE COLUMN HOLDS A PATH AND NOT A URL
--
-- A URL in a user-writable column is a URL the client can set to anything, and
-- something will eventually render it. A path is scoped by the policies below --
-- it can only name an object inside this user's own folder -- so the worst a
-- tampered value can do is point at a file that does not exist. The signed URL is
-- minted at read time from the path, and expires.
--
-- WHY THE BUCKET IS PRIVATE
--
-- A public bucket would make rendering a plain URL with no signing, which is
-- tempting and wrong here. v38 already set the privacy posture for this app: the
-- logo catalog is padded so the REQUEST SET discloses nothing about the user. A
-- world-readable photo of the user's face, at a URL that outlives any session, is
-- a larger disclosure than the thing that padding protects. Unguessable is not the
-- same as private.
--
-- MIME TYPE IS DELIBERATELY A SINGLE ENTRY
--
-- The client re-encodes whatever the photo picker hands it (HEIC, PNG, whatever
-- the camera produced) to a downscaled JPEG before upload, so JPEG is the only
-- thing this bucket ever legitimately receives. Listing PNG "just in case" would
-- widen what an attacker with a session can store without widening what the app
-- can use.
--
-- 2 MiB is generous: a 512px JPEG at 0.8 quality is 50-150 KB. The limit exists to
-- bound abuse, not to be reached.

alter table public.profiles
  add column if not exists avatar_path text;

comment on column public.profiles.avatar_path is
  'Storage object path of the profile picture, `<uid>/<epoch>.jpg`, or null for '
  'none. A PATH, never a URL: the storage policies scope it to the owner''s own '
  'folder, so a tampered value cannot name someone else''s object. Every upload '
  'writes a new path, which makes the path a cache key -- see Migration #11.';

-- The seventh user-owned column becomes the eighth. The boundary is unchanged:
-- the client may write what the user asserts, and nothing the sync or the engine
-- owns. A picture is as user-owned as a nickname.
grant update (avatar_path) on public.profiles to authenticated;

-- Bucket. `on conflict do update` rather than `do nothing` so a reset converges on
-- these limits instead of silently keeping whatever a previous run created.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 2097152, array['image/jpeg'])
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Four policies, one per verb, all saying the same thing: the first path segment
-- must be the caller's own uid.
--
-- UPDATE and DELETE are both granted because "change my picture" and "remove my
-- picture" are things the user must be able to do. INSERT alone would accumulate
-- objects the owner cannot clear.
--
-- WHY `if not exists` BLOCKS AND NOT `drop policy if exists`
--
-- Postgres has no `create policy if not exists`, so the obvious idempotent form is
-- a drop-then-create. That form was written first and MEASURED: it emits four
-- `NOTICE ... does not exist, skipping` lines on every fresh `db reset`. CI's gate
-- greps for `warning:` so it would have stayed green, which is precisely why this
-- is worth being careful about -- v18 set the standard that the CLI log stays
-- clean, and a log with routine noise in it is a log nobody reads.
--
-- Suppressing the notices with `client_min_messages` was the other candidate and
-- is worse: session-scoped it would mask warnings from LATER migrations and quietly
-- weaken the gate, and `set local` outside a transaction block raises a WARNING of
-- its own, tripping the very check it was meant to satisfy.

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'Avatars are readable by their owner'
  ) then
    create policy "Avatars are readable by their owner"
      on storage.objects for select to authenticated
      using (
        bucket_id = 'avatars'
        and (storage.foldername(name))[1] = auth.uid()::text
      );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'Avatars are writable by their owner'
  ) then
    create policy "Avatars are writable by their owner"
      on storage.objects for insert to authenticated
      with check (
        bucket_id = 'avatars'
        and (storage.foldername(name))[1] = auth.uid()::text
      );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'Avatars are replaceable by their owner'
  ) then
    create policy "Avatars are replaceable by their owner"
      on storage.objects for update to authenticated
      using (
        bucket_id = 'avatars'
        and (storage.foldername(name))[1] = auth.uid()::text
      )
      with check (
        bucket_id = 'avatars'
        and (storage.foldername(name))[1] = auth.uid()::text
      );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'Avatars are removable by their owner'
  ) then
    create policy "Avatars are removable by their owner"
      on storage.objects for delete to authenticated
      using (
        bucket_id = 'avatars'
        and (storage.foldername(name))[1] = auth.uid()::text
      );
  end if;
end $$;
