/// Validates generated application configuration before Audius is composed.
///
/// This boundary keeps missing or blank bundle values from registering live
/// Audius infrastructure while retaining only the public key the API requires.
struct AudiusConfiguration: Equatable, Sendable {
    let apiKey: String

    /// Creates configuration only when the generated bundle value contains a key.
    ///
    /// - Parameter apiKey: The optional public key read at the application boundary.
    init?(apiKey: String?) {
        guard
            let apiKey = apiKey?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !apiKey.isEmpty
        else {
            return nil
        }
        self.apiKey = apiKey
    }
}
