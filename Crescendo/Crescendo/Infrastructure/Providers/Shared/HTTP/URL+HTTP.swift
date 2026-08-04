import Foundation

extension URL {
    /// Creates a URL only when an external string uses HTTP or HTTPS.
    ///
    /// - Parameter httpString: The untrusted URL string supplied by a provider.
    init?(httpString: String) {
        guard
            let url = Self(string: httpString),
            let scheme = url.scheme?.lowercased()
        else {
            return nil
        }

        switch scheme {
        case "http", "https":
            self = url
        default:
            return nil
        }
    }
}
