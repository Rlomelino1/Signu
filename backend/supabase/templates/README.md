# Auth email templates

The two emails Signu actually sends. Registered in `supabase/config.toml` under
`[auth.email.template.recovery]` and `[auth.email.template.confirmation]`.

**Why the reasoning lives here and not in the HTML.** Comments in an email template
are *delivered*: they sit in the source the recipient can open with "show original".
An earlier draft explained the Outlook constraints and named `Theme.swift` inline,
which would have shipped internal notes to every inbox — and worse, a `{{ .Email }}`
mentioned in prose is substituted like any other, putting the address in the source
an extra time. The HTML files carry no comments at all.

## Which templates exist, and which deliberately do not

| Template | Sent when | Included |
|---|---|---|
| `confirmation` | signup, because `enable_confirmations = true` | yes |
| `recovery` | 17d's reset, and the Settings row that reuses it | yes |
| `email_change` | changing an address | no — the app has no change-email UI, so it is unreachable |
| `invite`, `magic_link`, `reauthentication` | — | no — this app never sends them |

The reported item was the reset email. The confirmation one is included because
`enable_confirmations = true` is non-negotiable here (the auth gate rests on a
session implying a verified address), which makes it the **first** email any account
receives: fixing only the reset would fix the second impression and not the first.

## Construction rules, and why each one is not a preference

- **Table layout, inline styles.** Outlook renders no flexbox and strips `<style>`
  blocks, so a stylesheet degrades to unstyled text in the client most likely to
  open it. Every colour is stated on the element that uses it.
- **One image, with a fallback that still reads as the brand (v51).** The mark is
  two counter-rotated arcs, not a letter, so no font substitutes for it — a styled
  "S" was the wrong mark, which is why v49's blanket "no images" rule was narrowed
  rather than kept. Gmail proxies and displays images by default and Apple Mail
  loads them; Outlook desktop blocks them, and there the ink `<td>` plus
  `alt="Signu"` in paper-on-ink still carries it. SVG is not an option (Gmail drops
  it) and neither is a `data:` URI (Gmail strips those too), so it has to be hosted.
  - Source of truth: `assets/signu-mark-80.png` — 80×80, 2.6 KB, derived from the
    1024 app icon with alpha stripped, per v37.
  - Served from the **public** `brand` bucket (Migration #12) at
    `https://<ref>.supabase.co/storage/v1/object/public/brand/signu-mark-80.png`.
    Public because a mail client holds no session and an email outlives any signed
    URL's expiry — the opposite requirement to Migration #11's private avatars.
  - **Placing the asset is a one-off step per environment**, like Migration #6's
    Vault secrets, because a binary does not belong in a migration:
    `supabase storage cp supabase/templates/assets/signu-mark-80.png ss:///brand/signu-mark-80.png`
  - Rendered at 40×40 from an 80×80 source, so it stays sharp on retina without
    paying for a larger file.
- **The link appears twice**, as a button and as selectable text, because a client
  that strips anchor styling still leaves something the reader can copy.
- **Palette copied from `frontend/Signu/DesignSystem/Theme.swift`**: paper `#EFEDE6`,
  surface `#FAF9F4`, ink `#2E2924`, on-ink `#F6F4EE`, text `#27231C`, secondary
  `#807C71`, hairline `#E2DFD4`.
- **Pure ASCII**, with `&mdash;` for the em dashes. GoTrue does declare
  `charset=UTF-8`, so raw UTF-8 would almost certainly survive — but "almost
  certainly" is doing work in the one email a locked-out user needs to read, and an
  entity depends on no charset negotiation or transport encoding at all. Verified by
  counting: zero bytes above 0x7F in either file.

## Copy that had to be checked rather than written

- **"within the hour"** is `otp_expiry = 3600` in `config.toml`, not an assumption.
- An earlier draft of `confirmation.html` said the bank connection "is read-only" and
  that Signu "cannot" move money. **Cut.** The Pluggy connector payload advertises
  `supportsPaymentInitiation`, so that claim needs the consent scope verified before
  it goes in writing to a user. It now says Signu only ever reads, which is
  defensible from what the app does.

## Deploying them

`supabase config push` sends the **whole auth config**, has no dry-run, and there is
no `supabase config pull` to diff against first — checked. `config.toml`'s own
comment records what that cost once already: pushing it while
`enable_confirmations` was at the CLI default would have silently disabled email
confirmation in production, and signup would have started returning live sessions
for unverified addresses with no error anywhere.

So the templates are additive but the push is not scoped to them.

**Use the dashboard** (Authentication → Emails): paste both bodies and both subjects.
That was decided on evidence rather than caution:

- **No `config push` has ever been run against this project.** The spec never
  records one, and the only commit touching the phrase (`09c28a1`) added the warning
  comment rather than performing a push. So this file has never been reconciled
  wholesale with production — exactly one setting was ever checked by hand.
- The file holds **74 auth settings**, and a first push applies all of them at once.
  At least one is wrong for production: `max_frequency = "1s"` is the CLI's
  local-dev default against production's 60s, so pushing would relax the
  server-side rate limit on reset emails to one second — removing the protection
  v19's countdown exists to make visible. See the comment on that line.
- There is no way to check the rest. `supabase config pull` does not exist
  (verified), so nothing here can diff production's auth config first.

**The drift this creates is real and is accepted deliberately.** Migration #6's
header is right that dashboard config drifts invisibly from the spec — which is why
the templates and their registration above are COMMITTED: the repo stays the source
of truth and the dashboard is only today's delivery mechanism. The proper fix is to
reconcile all 74 settings against production as its own task, after which
`config push` becomes the right tool for these and everything else.
