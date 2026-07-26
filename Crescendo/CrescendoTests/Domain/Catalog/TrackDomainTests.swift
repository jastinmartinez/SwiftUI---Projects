import Testing

@testable import Crescendo

struct TrackDomainTests {
    @Test
    func nativeIdentityIsQualifiedByProvider() {
        let jamendo = TrackID(providerID: .jamendo, nativeID: "42")
        let localMusic = TrackID(providerID: .localMusic, nativeID: "42")

        #expect(jamendo != localMusic)
    }
}
