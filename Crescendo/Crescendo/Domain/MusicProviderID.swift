/// Identifies a music provider independently from any provider SDK type.
struct MusicProviderID: Hashable, RawRepresentable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral rawValue: String) { self.init(rawValue: rawValue) }
}
