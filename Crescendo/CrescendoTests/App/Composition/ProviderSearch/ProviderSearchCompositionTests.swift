import Foundation
import Testing

@testable import Crescendo

struct ProviderSearchCompositionTests {
    @Test
    func libraryIsTheOnlyRequiredProvider() {
        let composition = ProviderSearchComposition(
            library: Self.client(providerID: .library),
            jamendo: nil,
            audius: nil
        )

        #expect(composition.providerIDs == [.library])
        #expect(composition.clients[.library] != nil)
        #expect(composition.clients[.jamendo] == nil)
        #expect(composition.clients[.audius] == nil)
    }

    @Test
    func presentProvidersRetainDeterministicOrderAndIdentity() async throws {
        let composition = ProviderSearchComposition(
            library: Self.client(providerID: .library),
            jamendo: Self.client(providerID: .jamendo),
            audius: Self.client(providerID: .audius)
        )

        #expect(composition.providerIDs == [.library, .jamendo, .audius])

        for providerID in composition.providerIDs {
            let client = try #require(composition.clients[providerID])
            let page = try await client.searchPage(
                .initial(query: "fixture"),
                20
            )
            #expect(page.tracks.map(\.id.providerID) == [providerID])
        }
    }

    private static func client(providerID: ProviderID) -> ProviderSearchClient {
        ProviderSearchClient(
            searchPage: { _, _ in
                SearchPage(
                    tracks: [
                        Track(
                            id: TrackID(
                                providerID: providerID,
                                nativeID: "fixture"
                            ),
                            title: "Fixture",
                            artistName: "Composition Tests",
                            albumTitle: nil,
                            artworkURL: nil,
                            duration: nil,
                            playbackURL: URL(
                                fileURLWithPath: "/fixture.mp3"
                            )
                        )
                    ],
                    nextCursor: nil
                )
            }
        )
    }
}
