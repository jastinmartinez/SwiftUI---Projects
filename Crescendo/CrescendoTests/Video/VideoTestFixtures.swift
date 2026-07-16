import Foundation
import Testing

/// Creates shared values used by Video feature tests.
enum VideoTestFixtures {
    static func url(_ path: String) throws -> URL {
        try #require(URL(string: "https://example.com/\(path)"))
    }
}
