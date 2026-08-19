
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
