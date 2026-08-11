import Foundation
import Supabase

/// The one `SupabaseClient` in the app.
///
/// Single instance on purpose. `SessionProviding` deliberately never exposes a
/// token — "the gate above it never learns what a token is" — so the data
/// provider cannot be handed one. Instead both providers share this client and
/// its auth module owns the session: `client.from(…)` attaches whatever token is
/// current, and the token never crosses a protocol boundary. Two clients would
/// mean two sessions, and the data provider would read as signed-out moments
/// after the gate said otherwise.
enum SupabaseClientProvider {
    static let shared: SupabaseClient = SupabaseClient(
        supabaseURL: URL(string: SupabaseConfig.url)!,
        supabaseKey: SupabaseConfig.anonKey
    )
}

/// Project coordinates.
///
/// The anon key is committed deliberately. It is a **public** client credential
/// by design — it identifies the project and nothing more, carries the `anon`
/// role, and every table it can reach is behind RLS with a `user_id` predicate
/// (Migration #1). Security here comes from the policies, not from hiding this
/// string; treating it as a secret would be cargo-culting while the real
/// boundary sits in the database.
///
/// What must NEVER appear in this file: the `service_role` key, which bypasses
/// RLS, or `SYNC_SECRET`. Those live only in Edge Function environments and
/// Vault, and a client that held either would make every user's data reachable.
enum SupabaseConfig {
    static let url = "https://yrdihsizftdmlbytwxtg.supabase.co"

    static let anonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" +
        ".eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlyZGloc2l6ZnRkbWxieXR3eHRnIiwicm9sZSI6ImFub24i" +
        "LCJpYXQiOjE3ODM2NTgxMDMsImV4cCI6MjA5OTIzNDEwM30" +
        ".fPtLF9GkLeEROmlJXw7o6UX3VZYodPjoMtuMmps_jW0"
}
