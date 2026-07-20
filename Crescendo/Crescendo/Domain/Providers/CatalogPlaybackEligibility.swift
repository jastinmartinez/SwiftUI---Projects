/// Describes whether the current account may play catalog content.
///
/// Eligibility remains independent from provider authorization.
enum CatalogPlaybackEligibility: Equatable, Sendable {
    case unknown
    case eligible
    case ineligible
}
