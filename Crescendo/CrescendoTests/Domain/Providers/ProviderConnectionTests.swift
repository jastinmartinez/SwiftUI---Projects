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
            providerID: .testProvider,
            requestID: UUID(0)
        ),
        .denied(providerID: .testProvider),
        .restricted(providerID: .testProvider),
        .failed(providerID: .testProvider),
    ])
    func unresolvedConnectionExposesOnlyProvider(
        connection: ProviderConnection
    ) {
        #expect(connection.providerID == .testProvider)
        #expect(connection.access == nil)
    }

    @Test
    func connectedExposesProviderAndAccess() {
        let access = MusicProviderAccess(
            authorization: .authorized,
            playbackEligibility: .eligible
        )
        let connection = ProviderConnection.connected(
            providerID: .testProvider,
            access: access
        )

        #expect(connection.providerID == .testProvider)
        #expect(connection.access == access)
    }
}
