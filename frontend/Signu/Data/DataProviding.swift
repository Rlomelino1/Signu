import Foundation

/// Data access boundary. Views never compute doctrine — "UI reads state,
/// never guesses" — so screen-shaped payload methods (home payload, subs-tab
/// payload, detail timeline…) will be added here as each screen lands,
/// mirroring the endpoints the backend will eventually serve. A Supabase
/// provider then slots in behind this protocol without touching views.
///
/// `@MainActor` because every consumer is a SwiftUI view and the live provider
/// caches rows in mutable state that only the main actor may touch. Stating it on
/// the protocol rather than the conformer is what makes that safe: an @MainActor
/// class conforming to a non-isolated protocol warns today and is an **error in
/// the Swift 6 language mode**, because a caller holding the existential could
/// invoke it from anywhere. Isolating the boundary itself removes the hole rather
/// than silencing the diagnostic.
@MainActor
protocol SignuDataProviding {
    /// "Today" as the provider sees it. The mock provider pins this so
    /// previews are deterministic; the live provider returns the real date.
    var today: Date { get }

    func profile() async throws -> Profile
    /// Screen payload for Home — assembled per the home screen contract.
    func homePayload() async throws -> HomePayload
    /// Screen payload for the Subscriptions tab — per the subs tab contract.
    func subsPayload() async throws -> SubsPayload
    /// Screen payload for the Review screen (9a) — possible runs to decide on.
    func reviewPayload() async throws -> ReviewPayload
    /// Screen payload for the subscription detail screen. nil if not found.
    func detailPayload(subscriptionId: UUID) async throws -> DetailPayload?
    /// Settings screen (12a/12d).
    func settingsPayload() async throws -> SettingsPayload
    /// Connection detail (12b). nil if not found.
    func connectionDetailPayload(connectionId: UUID) async throws -> ConnectionDetailPayload?
    /// Attributed-subscriptions list (13a). nil if not found.
    func attributedSubsPayload(connectionId: UUID) async throws -> AttributedSubsPayload?
    /// Discards the cached graph and reads it again, answering whether anything
    /// actually changed.
    ///
    /// Until this existed the app could not notice data it had not written
    /// itself. The provider loads the whole graph once and invalidates only on
    /// its own writes, so rows arriving server-side — the 15:30 UTC sync, the
    /// detection pass behind a fresh bank link — stayed invisible for the life of
    /// the session. Switching tabs did not help: the screen rebuilds, its `.task`
    /// runs again, and `ensureLoaded()` hands back the same cached rows.
    ///
    /// The Bool exists so a caller can avoid rebuilding a screen for nothing. A
    /// pull-to-refresh ignores it (the user asked, so the screen re-reads either
    /// way); a foreground refresh uses it, because throwing away someone's scroll
    /// position to show them what they were already looking at is worse than not
    /// refreshing at all.
    @discardableResult
    func refresh() async throws -> Bool

    /// MERCHANT_CATALOG. Shared reference data rather than the user's rows, so it
    /// carries no `user_id` and is identical for every account — which is the
    /// property the logo prefetch depends on (see `LogoStore`).
    func merchantCatalog() async throws -> [MerchantCatalogEntry]

    /// The renewal calendar, one month at a time. Takes any date in the month
    /// rather than a month index, so callers never assemble one.
    func calendarPayload(monthContaining date: Date) async throws -> CalendarPayload
    /// Delete-account scope counts (14a).
    func deleteAccountScope() async throws -> DeleteAccountScope
    func connections() async throws -> [Connection]
    func bankAccounts() async throws -> [BankAccount]
    func subscriptions() async throws -> [Subscription]
    func runs(subscriptionId: UUID) async throws -> [SubscriptionRun]
    func charges(runId: UUID) async throws -> [Charge]

    // MARK: - Writes
    //
    // The app's first write path. Until it existed every state-changing control in
    // the UI called a closure nobody supplied, so the whole interface was a shell:
    // the reminder toggle flipped its own local state, Restore hid a row until the
    // next launch, and Dismiss did nothing at all.
    //
    // ONLY user-owned columns appear here, and that is a permission boundary rather
    // than a style choice. Migration #1 grants `authenticated` a column-scoped
    // UPDATE on exactly seven columns; a write to anything else fails at the
    // database no matter what this protocol claims. So the shape of this section is
    // dictated by the grants, and cannot drift from them without failing loudly.
    //
    // What is therefore NOT here as a column write, and goes through an Edge
    // Function instead: confirming a suggestion (`subscription_run.status` +
    // `identification`), marking a run cancelled (`cancelled_date`), removing a
    // bank link and deleting an account. Runs are engine-owned, `authenticated`
    // holds no UPDATE grant on that table at all, and no DELETE anywhere ever.
    // Those four are the second group below (v30) — same protocol, different
    // enforcement, and the difference is worth seeing in one file.

    /// The detail screen's reminder toggle. `nil` turns reminders off — the
    /// nullable column *is* the switch (v5), so there is no separate flag.
    /// On maps to 2 days, per the detail contract.
    func setReminder(subscriptionId: UUID, remindBeforeDays: Int?) async throws

    /// The detail screen's Rename. Writes `nickname`, NOT `service_name`:
    /// the engine's name for a merchant is its own, and `displayName` already
    /// prefers the nickname when there is one. Passing nil clears the nickname
    /// and the engine's name shows through again — which is why this is one
    /// method and not a rename plus a reset.
    ///
    /// Deliberately does not touch `identification`. That column is not in the
    /// client's grant, and it does not need to be: `user_renamed` exists to
    /// freeze `service_name` against the engine, and nothing here writes it.
    func setNickname(subscriptionId: UUID, nickname: String?) async throws

    /// The detail screen's Change category. Seeded by detection, user-editable;
    /// nil clears it back to uncategorised.
    func setCategory(subscriptionId: UUID, category: String?) async throws

    /// Review's Dismiss (`true`) and Settings' Restore (`false`).
    /// Restore is exactly `ignored = false` and nothing more: the run returns to
    /// `possible` and resurfaces in review, because it never left that state.
    func setIgnored(subscriptionId: UUID, ignored: Bool) async throws

    /// Settings' edit-profile sheet. `display_name` has been in the client's
    /// column-scoped grant since Migration #1 and had no writer until v47.
    ///
    /// Passing nil clears it, and the read falls back to the email address again —
    /// the same shape as `setNickname`, and for the same reason: "no name" is a
    /// state the user is allowed to return to.
    func setDisplayName(_ name: String?) async throws

    /// Uploads a **downscaled JPEG** and points `profiles.avatar_path` at it.
    ///
    /// The caller passes finished bytes rather than a `UIImage`, so the encoding
    /// rule lives in one testable place (`AvatarImage`) instead of in whichever
    /// screen happens to call this. Each upload writes a NEW path, which is what
    /// makes the path a cache key — see Migration #11.
    func setAvatar(jpeg: Data) async throws

    /// Clears the picture: the object is deleted and the column set to null.
    ///
    /// The column goes last. Nulling first and failing to delete leaves an
    /// orphaned object the owner can no longer name; deleting first and failing to
    /// null leaves a path to nothing, which renders as the monogram — the same as
    /// no picture. Only one of those two orders degrades honestly.
    func removeAvatar() async throws

    /// The bytes behind `avatar_path`, for the cache to store on disk.
    ///
    /// On the provider rather than in `AvatarStore` because the bucket is private:
    /// reading it needs the authenticated client, and the store must not hold one.
    func avatarData(path: String) async throws -> Data

    // MARK: - Writes the client is not granted (Edge Functions, v30)
    //
    // These four throw where the two above swallow. A column write the user can
    // see the result of can afford `try?` at the call site — the toggle already
    // moved, the next read tells the truth. These change state the screen cannot
    // show and, in two cases, delete data irreversibly, so an error that never
    // surfaced would leave the user believing something that did not happen.

    /// Review's *Track it* (9a). Takes the **run** id, because a suggestion IS a
    /// run: `possible` is a run status, and lifting it out of that state is the
    /// whole write. `billingInterval` is the R4 sheet's answer and must be nil
    /// for R3, whose cadence the engine measured — the server refuses the
    /// mismatch rather than guessing which one it is looking at.
    func confirmSuggestion(runId: UUID, billingInterval: BillingInterval?) async throws

    /// The detail screen's *Mark cancelled* (10a). Takes the subscription, not
    /// the run: run identity is engine business and is re-derived on every
    /// detection pass, so the server resolves the newest run itself.
    func markCancelled(subscriptionId: UUID) async throws

    /// Remove a bank link (12c). `deleteHistory` is the sheet's radio choice and
    /// is captured before the destructive tap for a reason that is not
    /// cosmetic: attribution runs through `charge.transaction_id`, which the
    /// connection's own deletion NULLs, so the answer is unrecoverable
    /// afterwards.
    func removeConnection(connectionId: UUID, deleteHistory: Bool) async throws

    /// Delete the account (14a). No id parameter, ever — the account deleted is
    /// the one that owns the session. The caller still signs out afterwards.
    func deleteAccount() async throws

    // MARK: - Connecting a bank
    //
    // Two calls around one widget. Pluggy Connect runs client-side and cannot
    // hold the API secret, so the server mints a short-lived token scoped to the
    // one item the session produces; the widget hands back an item id; the server
    // turns that into a connection and syncs it.
    //
    // The item id is NOT trusted on the way back. `connect-token` stamps the
    // caller's user id onto the item as `clientUserId`, and `register-connection`
    // refuses any item that does not carry it — otherwise an item id would be a
    // bearer token for someone else's transactions.

    /// A token for the Connect widget. `connectionId` re-opens an existing link
    /// for re-authentication (12b's Reconnect, Home's needs-action banner);
    /// nil opens the connector list to add a new one.
    func connectSession(connectionId: UUID?) async throws -> ConnectSession

    /// Registers the item the widget produced and runs the first sync, so one tap
    /// produces cards, transactions and detected subscriptions rather than an
    /// empty row waiting for tomorrow's cron.
    func registerConnection(itemId: String) async throws
}

/// What the Connect widget needs to start.
struct ConnectSession: Equatable {
    let accessToken: String
    /// True only for the mock provider, which has no real widget to run. The
    /// flow renders a labelled stand-in rather than a web view that would fail
    /// to load — previews and UI tests keep working, and nothing pretends a
    /// simulated link is a real one.
    var simulated = false
}
