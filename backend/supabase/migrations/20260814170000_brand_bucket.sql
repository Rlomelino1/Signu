-- Migration #12 — a public bucket for the mark an email can load
-- Source of truth: subscription-tracker-data-model.md (v51, 2026-08-14)
--
-- ADDITIVE ONLY: one storage bucket. No table, column, constraint, index, RLS
-- policy or grant is touched, and no policy is added -- see below for why that is
-- correct rather than an omission.
--
-- WHY A HOSTED IMAGE AT ALL
--
-- The auth emails (v49) drew the brand mark as a styled letter "S" in an ink
-- square, because v49's rule was "no images": clients block remote ones and a data:
-- URI is stripped by Gmail. But the real mark is not a letter -- it is two
-- counter-rotated arcs, and no font substitutes for it. So the choice is a hosted
-- PNG or a wrong mark, and the wrong mark loses.
--
-- The v49 reasoning still holds where it applies: this is ONE small image with a
-- degradation path (see the templates), not a design that depends on images
-- loading. Gmail proxies and displays images by default and Apple Mail loads them;
-- Outlook desktop blocks them, and there the ink cell plus alt text still reads as
-- the brand.
--
-- WHY PUBLIC, WHEN MIGRATION #11's BUCKET IS PRIVATE
--
-- Opposite requirements, not an inconsistency. #11 holds photographs of the user's
-- face, which is why it is private and owner-scoped. This holds a logo whose entire
-- job is to be fetched, unauthenticated, by a mail client that will never hold a
-- session. A private bucket cannot serve that: a signed URL expires, and an email
-- outlives any expiry we could set.
--
-- WHY NO POLICIES
--
-- A public bucket is served through `/storage/v1/object/public/...`, which does not
-- consult `storage.objects` RLS for reads, so a SELECT policy would be decoration.
-- Writes are deliberately left with no policy at all: nothing in the app uploads
-- here, and the asset is placed once with `supabase storage cp`, which authenticates
-- as the project owner and bypasses RLS. `authenticated` therefore cannot write to
-- this bucket, which is the correct posture for a bucket whose contents the app
-- treats as read-only reference data.
--
-- THE ASSET IS COMMITTED, THE UPLOAD IS A STEP
--
-- `supabase/templates/assets/signu-mark-80.png` is the source of truth (80x80,
-- 2.6 KB, derived from the 1024 app icon, alpha stripped as v37 required). Placing
-- it in the bucket is a one-off per environment, documented in
-- `supabase/templates/README.md` -- the same shape as Migration #6's Vault secrets,
-- and for the same reason: a binary does not belong in a migration.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('brand', 'brand', true, 1048576, array['image/png'])
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;
