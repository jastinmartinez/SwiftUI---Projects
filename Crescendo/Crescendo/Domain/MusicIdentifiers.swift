struct MusicProviderID: Hashable, RawRepresentable, Sendable,
  ExpressibleByStringLiteral {
  let rawValue: String

  init(rawValue: String) { self.rawValue = rawValue }
  init(stringLiteral rawValue: String) { self.init(rawValue: rawValue) }
}

struct MusicItemID: Hashable, Sendable {
  let providerID: MusicProviderID
  let nativeID: String
}
