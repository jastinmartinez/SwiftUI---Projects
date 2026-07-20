/// Describes whether the user has granted access to a music provider.
enum MusicAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}
