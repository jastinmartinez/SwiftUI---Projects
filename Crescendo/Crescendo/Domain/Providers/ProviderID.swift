/// Identifies a provider independently from any provider SDK type.
struct ProviderID: Hashable, RawRepresentable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral rawValue: String) { self.init(rawValue: rawValue) }
}

extension ProviderID {
    /// The identifier of Crescendo's Apple Music provider.
    static let appleMusic = Self(rawValue: "apple-music")
}
