enum MusicAuthorizationState: Equatable, Sendable {
  case notDetermined
  case authorized
  case denied
  case restricted
}

enum CatalogPlaybackEligibility: Equatable, Sendable {
  case unknown
  case eligible
  case ineligible
}

struct MusicProviderAccess: Equatable, Sendable {
  let authorization: MusicAuthorizationState
  let playbackEligibility: CatalogPlaybackEligibility
}

enum MusicProviderError: Error, Equatable, Sendable {
  case noActiveProvider
  case authorizationDenied
  case authorizationRestricted
  case unavailable
  case network
  case playbackFailed
}
