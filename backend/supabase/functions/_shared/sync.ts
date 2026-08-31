
export type Held = { id: string; provider_tx_id: string }

export type WithdrawalDecision =
  | { kind: 'withdraw'; ids: string[] }
  | { kind: 'noop'; reason: string }
  | { kind: 'refuse'; reason: string }

export function withdrawalDecision(
  feedIds: readonly string[],
  held: readonly Held[],
  truncated: boolean,
): WithdrawalDecision {
  if (truncated) {
    return { kind: 'noop', reason: 'response truncated, so absence is not evidence' }
  }

  if (feedIds.length === 0 && held.length > 0) {
    return {
      kind: 'refuse',
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

export type ApplyDecision =
  | { kind: 'apply' }
  | { kind: 'refuse'; reason: string }

// The same principle as withdrawalDecision, one stage later: an engine pass
// that finds NOTHING where runs exist is more likely reporting degraded input
// than a world where every subscription vanished at once. The 2026-08-31
// incident is the proof: the Pluggy trial lapsed, merchant enrichment went
// null, grouping shattered, and an all-green pipeline deleted every run.
// Partial disappearance is still trusted — one run ending is ordinary; all of
// them at once, with nothing detected to replace them, is refused.
export function detectionApplyDecision(
  desiredSubscriptions: number,
  storedRuns: number,
): ApplyDecision {
  if (desiredSubscriptions === 0 && storedRuns > 0) {
    return {
      kind: 'refuse',
      reason: `detection found nothing against ${storedRuns} stored run(s): ` +
        `refusing to apply a total wipe, since degraded provider data reads ` +
        `exactly like this (pass allowWipe to override)`,
    }
  }
  return { kind: 'apply' }
}
