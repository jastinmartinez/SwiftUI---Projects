import Foundation
import Testing

@testable import Crescendo

struct TrackDomainTests {
    @Test
    func nativeIdentityIsQualifiedByProvider() {
        let jamendo = TrackID(providerID: .jamendo, nativeID: "42")
        let library = TrackID(providerID: .library, nativeID: "42")

        #expect(jamendo != library)
    }

    @Test
    func libraryIdentityRoundTripsThroughTheCatalogRepresentation() throws {
        let identity = TrackID(
            providerID: .library,
            nativeID: "A4C5B590-64AE-44A7-A331-A83594280686"
        )

        let data = try JSONEncoder().encode(identity)
        let decoded = try JSONDecoder().decode(TrackID.self, from: data)

        #expect(decoded == identity)
    }
}
