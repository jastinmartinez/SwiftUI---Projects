/// Validated public client configuration required by the Jamendo API.
struct JamendoConfiguration: Equatable, Sendable {
    let clientID: String

    init?(clientID: String?) {
        guard
            let clientID = clientID?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !clientID.isEmpty
        else {
            return nil
        }
        self.clientID = clientID
    }
}
