import Foundation
import Testing

@testable import Crescendo

struct ProviderConnectionTests {
    @Test
    func disconnectedHasNoProviderOrAccess() {
        let connection = ProviderConnection.disconnected

        #expect(connection.providerID == nil)
        #expect(connection.access == nil)
    }

    @Test(arguments: [
        ProviderConnection.connecting(
            providerID: .appleMusic,
            requestID: UUID(0)
        ),
        .denied(providerID: .appleMusic),
        .restricted(providerID: .appleMusic),
        .failed(providerID: .appleMusic),
    ])
    func unresolvedConnectionExposesOnlyProvider(
        connection: ProviderConnection
    ) {
        #expect(connection.providerID == .appleMusic)
        #expect(connection.access == nil)
    }

    @Test
    func connectedExposesProviderAndAccess() {
        let access = MusicProviderAccess(
            authorization: .authorized,
            playbackEligibility: .eligible
        )
        let connection = ProviderConnection.connected(
            providerID: .appleMusic,
            access: access
        )

        #expect(connection.providerID == .appleMusic)
        #expect(connection.access == access)
    }
}
