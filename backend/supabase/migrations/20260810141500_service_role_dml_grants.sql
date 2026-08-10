-- Migration #3 — service_role DML grants
-- Source of truth: subscription-tracker-data-model.md (v22, 2026-08-10)
--
-- ADDITIVE ONLY. Migration #1 is applied to the remote, so in-place correction
-- is closed (v17: "in-place correction is safe only before first apply").
--
-- WHY THIS EXISTS
--
-- Migration #1 locked the posture "All writes go through Edge Functions (service
-- role, bypasses RLS)". Half of that was true and half was never implemented:
--
--   * bypasses RLS  -- TRUE. service_role carries rolbypassrls = t.
--   * writes        -- FALSE. Migration #1's grant block names only `anon` and
--                      `authenticated`:
--                        revoke all ... from anon, authenticated;
--                        grant select ... to authenticated;
--                      service_role is never mentioned, and it does not inherit
--                      from authenticated (no pg_auth_members edge).
--
-- Observed ACL before this migration, on all seven tables:
--
--     relacl = {postgres=arwdDxtm/postgres,
--               service_role=Dxtm/postgres,      <-- no a,r,w,d
--               authenticated=r/postgres}
--
-- So service_role held TRUNCATE, REFERENCES, TRIGGER and MAINTAIN but not
-- INSERT, SELECT, UPDATE or DELETE. Found by running pluggy-sync against the
-- local stack: it failed on its very first query with
--
--     HTTP 500  {"error": "select connection: permission denied for table connection"}
--
-- Stated explicitly rather than left to the platform. Supabase's default
-- privileges for tables created by `postgres` in `public` do not reliably confer
-- DML on service_role, and a permission that arrives by default is a permission
-- that can leave by default. This is the writer-states-everything doctrine
-- applied to grants: a capability the spec depends on has to be written down
-- somewhere a migration can prove.
--
-- No RLS policy changes. No column-scoped grants. The `authenticated` posture
-- from Migration #1 is untouched -- seven column-scoped UPDATE grants, SELECT
-- everywhere, no INSERT/DELETE ever, `anon` nothing.

grant select, insert, update, delete on
  public.profiles,
  public.connection,
  public.bank_account,
  public.transaction,
  public.subscription,
  public.subscription_run,
  public.charge
  to service_role;

-- Deliberately NOT granted:
--
--   * anon / authenticated       -- unchanged from Migration #1 on purpose. The
--                                   client reads through RLS and writes nothing.
--   * TRUNCATE                   -- service_role already holds it by default,
--                                   and nothing in the design truncates. Not
--                                   re-stated, because re-stating an inherited
--                                   privilege implies this migration governs it.
--   * sequence privileges        -- there are no sequences: every PK is a uuid
--                                   with gen_random_uuid().
