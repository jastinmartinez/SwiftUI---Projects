/// Identifies a provider independently from any provider SDK type.
struct ProviderID:
    Codable,
    Hashable,
    RawRepresentable,
    Sendable,
    ExpressibleByStringLiteral
{
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral rawValue: String) { self.init(rawValue: rawValue) }
}

extension ProviderID {
    static let jamendo = Self(rawValue: "jamendo")
    static let library = Self(rawValue: "library")
}
