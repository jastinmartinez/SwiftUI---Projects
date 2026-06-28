@testable import Filer
import Foundation
import Testing

@Suite("SupabaseConfig")
struct SupabaseConfigTests {
    // A Bundle stub backed by a plain dictionary, so the test never touches the real Info.plist.
    final class StubBundle: Bundle, @unchecked Sendable {
        let values: [String: Any]
        init(values: [String: Any]) {
            self.values = values
            super.init()
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) { fatalError("unused") }
        override func object(forInfoDictionaryKey key: String) -> Any? { values[key] }
    }

    @Test("requiredString returns the value when present")
    func requiredStringReadsValue() {
        let bundle = StubBundle(values: ["SUPABASE_BUCKET": "media"])
        #expect(bundle.requiredString("SUPABASE_BUCKET") == "media")
    }

    @Test("loadFromBundle builds the config from Info-dictionary keys")
    func loadFromBundleBuildsConfig() {
        let bundle = StubBundle(values: [
            "SUPABASE_URL": "https://xyz.supabase.co",
            "SUPABASE_ANON_KEY": "anon-123",
            "SUPABASE_BUCKET": "media",
        ])

        let config = SupabaseConfig.loadFromBundle(bundle)

        #expect(config == SupabaseConfig(
            projectURL: URL(string: "https://xyz.supabase.co")!,
            anonKey: "anon-123",
            bucket: "media"
        ))
    }
}
