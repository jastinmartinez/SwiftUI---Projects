import Foundation

extension Bundle {
    /// Reads a required Info-dictionary string, failing loud on a missing/blank key.
    /// These keys are wired from a gitignored Secrets.xcconfig; an absent value is a
    /// build-configuration error, not a runtime condition to handle.
    func requiredString(_ key: String) -> String {
        guard let value = object(forInfoDictionaryKey: key) as? String, !value.isEmpty else {
            fatalError("Missing required Info.plist key '\(key)' — check Secrets.xcconfig wiring.")
        }
        return value
    }
}

/// Pure data: the Supabase project coordinates. Not a dependency — an explicit input
/// to MediaRemoteStorageClient.make(config:); only liveValue loads it.
struct SupabaseConfig: Equatable {
    let projectURL: URL
    let anonKey: String
    let bucket: String
}

extension SupabaseConfig {
    /// Framework → domain factory. Fails loud on missing keys (build-config error).
    static func loadFromBundle(_ bundle: Bundle = .main) -> SupabaseConfig {
        SupabaseConfig(
            projectURL: URL(string: bundle.requiredString("SUPABASE_URL"))!,
            anonKey: bundle.requiredString("SUPABASE_ANON_KEY"),
            bucket: bundle.requiredString("SUPABASE_BUCKET")
        )
    }
}
