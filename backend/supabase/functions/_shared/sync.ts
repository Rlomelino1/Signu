// sync.ts — the sync-time decisions `pluggy-sync` must not make inline.
//
// Same shape as detection.ts, reminders.ts and actions.ts: a pure function over
// rows, testable without a database, leaving the Edge Function above it a
// load-decide-write shell. The reason this file exists at all is narrower than
// tidiness — CI runs `deno test backend/supabase/functions/_shared/` and nothing
// else, so a rule written inside `pluggy-sync/index.ts` is a rule no gate can
// check, and this particular rule decides whether a year of user assertions
// survives a bad response.

export type Held = { id: string; provider_tx_id: string }

/** A decision the caller applies, reports, or refuses to act on. `noop` and
 *  `refuse` are deliberately distinct: an empty window on a new account is
 *  ordinary, an empty window over rows we hold is not. */
export type WithdrawalDecision =
  | { kind: 'withdraw'; ids: string[] }
  | { kind: 'noop'; reason: string }
  | { kind: 'refuse'; reason: string }

/** Which held rows a response justifies marking withdrawn.
 *
 *  Withdrawal is inference from ABSENCE: Pluggy's transaction id is a content
 *  hash rather than a surrogate key, so a hash-breaking edit or a 1–3 day bank
 *  drop deletes the row and re-creates it under a new id. A row we hold that the
 *  feed no longer lists is therefore usually gone for real. Usually.
 *
 *  THE EMPTY RESPONSE IS THE DANGEROUS ONE, and it is not hypothetical: a
 *  revoked Open Finance consent answers 200 with a well-formed body and zero
 *  transactions. Read literally, every in-window row becomes "gone", so every one
 *  is marked withdrawn; detection then finds no candidates and `delete_run_ids`
 *  removes every non-frozen run, taking run-level assertions — confirmed
 *  suggestions, cancellations — with it while subscription-level ones survive.
 *  Re-running does not repair that: "re-runs repair" is a promise about DERIVED
 *  state, and an assertion is not derived.
 *
 *  So an empty feed against held rows is refused rather than obeyed. The refusal
 *  claims nothing about whether those rows still exist at the bank — it declines
 *  to treat silence as evidence, which is the same reasoning as the `truncated`
 *  gate and the same reasoning v61 applied to the applier's prune, scoped to one
 *  run so an empty payload could not wipe a history. `delete_run_ids` bypasses
 *  that prune entirely, which is why this guard has to sit as far upstream as
 *  the raw chain.
 *
 *  An empty feed with NOTHING held is not anomalous — a new account, or a window
 *  with no activity — and stays a plain no-op. Conflating the two would make
 *  first sync on a quiet account report a failure.
 *
 *  DELIBERATE LIMIT: only a fully empty feed is refused. A response returning one
 *  row where it returned two hundred is trusted, because no threshold separates
 *  "consent partially revoked" from "the user really did have one transaction
 *  this window" without inventing a number. Stated here so the narrowness reads
 *  as a decision rather than an oversight. */
export function withdrawalDecision(
  feedIds: readonly string[],
  held: readonly Held[],
  truncated: boolean,
): WithdrawalDecision {
  // Absence proves nothing about a response we know is incomplete. Checked first
  // because a truncated feed can also arrive empty, and then the truncation is
  // the honest explanation rather than the anomaly.
  if (truncated) {
    return { kind: 'noop', reason: 'response truncated, so absence is not evidence' }
  }

  if (feedIds.length === 0 && held.length > 0) {
    return {
      kind: 'refuse',
      // The counts are in the message because `last_sync_error` is where this
      // will actually be read, and "empty response" alone does not say how much
      // was at stake.
      reason:
        `empty transaction feed against ${held.length} held row(s) in the window: ` +
        `refusing to withdraw, since a revoked consent returns empty data rather ` +
        `than an error`,
    }
  }

  const feed = new Set(feedIds)
  const ids = held.filter((h) => !feed.has(h.provider_tx_id)).map((h) => h.id)
  if (ids.length === 0) {
    return { kind: 'noop', reason: 'every held row is still in the feed' }
  }
  return { kind: 'withdraw', ids }
}
