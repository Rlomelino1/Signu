import Foundation
import Supabase

enum SupabaseClientProvider {
    static let shared: SupabaseClient = SupabaseClient(
        supabaseURL: URL(string: SupabaseConfig.url)!,
        supabaseKey: SupabaseConfig.anonKey,
        options: SupabaseClientOptions(
            auth: SupabaseClientOptions.AuthOptions(
                redirectToURL: URL(string: SupabaseConfig.redirectURL)!
            )
        )
    )
}

enum SupabaseConfig {
    static let redirectURL = "signu://auth-callback"

    static let url = string("SupabaseURL", fallback: "https://config-missing.invalid")
    static let anonKey = string("SupabaseAnonKey", fallback: "")
    static let logoDevKey = string("LogoDevPublishableKey", fallback: "")

    private static let values: [String: String] = {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil),
              let dict = plist as? [String: Any]
        else { return [:] }
        return dict.compactMapValues { $0 as? String }
    }()

    private static func string(_ key: String, fallback: String) -> String {
        guard let value = values[key], !value.isEmpty else { return fallback }
        return value
    }
}
