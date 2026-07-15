struct MusicProviderCapabilities: Equatable, Sendable {
  let supportsCatalogSearch: Bool
  let supportsEmbeddedPlayback: Bool
  let supportsSeeking: Bool
  let supportsQueueReplacement: Bool
}
