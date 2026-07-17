import ComposableArchitecture
import Foundation
import Testing
import UIKit

@testable import Crescendo

@MainActor
struct SearchFeatureTests {
    @Test
    func successfulSearch() async {
        let accessCalls = LockIsolated<[String]>([])
        let song = makeSong()
        let store = TestStore(
            initialState: makeState(
                query: "result",
                phase: .idle,
                playbackEligibility: .unknown
            )
        ) {
            SearchFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.musicProvider.currentAccess = {
                accessCalls.withValue { $0.append("current") }
                return .init(authorization: .authorized, playbackEligibility: .eligible)
            }
            $0.musicProvider.requestAccess = {
                accessCalls.withValue { $0.append("request") }
                return .init(authorization: .denied, playbackEligibility: .unknown)
            }
            $0.musicProvider.search = { _, _ in [song] }
        }

        await store.send(.submitButtonTapped) {
            $0.phase = .loading(requestID: UUID(0), stage: .checkingAccess)
        }
        await store.receive(\.currentAccessResponse)
        await store.receive(\.accessResolved) {
            $0.playbackEligibility = .eligible
            $0.phase = .loading(requestID: UUID(0), stage: .searching)
        }
        await store.receive(\.searchResponse) {
            $0.phase = .loaded([song])
        }
        #expect(accessCalls.value == ["current"])
    }

    @Test
    func ineligibleAccountStillReceivesSearchResults() async {
        let song = makeSong()
        let store = TestStore(
            initialState: makeState(
                query: "result",
                phase: .idle,
                playbackEligibility: .unknown
            )
        ) {
            SearchFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.musicProvider.currentAccess = {
                .init(authorization: .authorized, playbackEligibility: .ineligible)
            }
            $0.musicProvider.search = { _, _ in [song] }
        }

        await store.send(.submitButtonTapped) {
            $0.phase = .loading(requestID: UUID(0), stage: .checkingAccess)
        }
        await store.receive(\.currentAccessResponse)
        await store.receive(\.accessResolved) {
            $0.playbackEligibility = .ineligible
            $0.phase = .loading(requestID: UUID(0), stage: .searching)
        }
        await store.receive(\.searchResponse) {
            $0.phase = .loaded([song])
        }
    }

    @Test
    func undeterminedAccessIsRequestedBeforeSearch() async {
        let accessCalls = LockIsolated<[String]>([])
        let song = makeSong()
        let store = TestStore(
            initialState: makeState(
                query: "result",
                phase: .idle,
                playbackEligibility: .unknown
            )
        ) {
            SearchFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.musicProvider.currentAccess = {
                accessCalls.withValue { $0.append("current") }
                return .init(authorization: .notDetermined, playbackEligibility: .unknown)
            }
            $0.musicProvider.requestAccess = {
                accessCalls.withValue { $0.append("request") }
                return .init(authorization: .authorized, playbackEligibility: .eligible)
            }
            $0.musicProvider.search = { _, _ in [song] }
        }

        await store.send(.submitButtonTapped) {
            $0.phase = .loading(requestID: UUID(0), stage: .checkingAccess)
        }
        await store.receive(\.currentAccessResponse) {
            $0.phase = .loading(requestID: UUID(0), stage: .requestingAccess)
        }
        await store.receive(\.requestAccessResponse)
        await store.receive(\.accessResolved) {
            $0.playbackEligibility = .eligible
            $0.phase = .loading(requestID: UUID(0), stage: .searching)
        }
        await store.receive(\.searchResponse) {
            $0.phase = .loaded([song])
        }
        #expect(accessCalls.value == ["current", "request"])
    }

    @Test
    func staleResponseIsIgnored() async {
        let state = makeState(
            query: "new",
            phase: .loading(requestID: UUID(2), stage: .searching),
            playbackEligibility: .unknown
        )
        let store = TestStore(initialState: state) { SearchFeature() }

        await store.send(.searchResponse(UUID(1), .success([])))
    }

    @Test
    func changingQueryInvalidatesLoadingSearch() async {
        let state = makeState(
            query: "old",
            phase: .loading(requestID: UUID(0), stage: .checkingAccess),
            playbackEligibility: .unknown
        )
        let store = TestStore(initialState: state) { SearchFeature() }

        await store.send(.queryChanged("new")) {
            $0.query = "new"
            $0.phase = .idle
        }
        await store.send(
            .currentAccessResponse(
                UUID(0),
                .init(authorization: .authorized, playbackEligibility: .eligible)
            )
        )
    }

    @Test
    func deniedAccessIsRecoverable() async {
        let store = TestStore(
            initialState: makeState(
                query: "term",
                phase: .idle,
                playbackEligibility: .unknown
            )
        ) {
            SearchFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.musicProvider.currentAccess = {
                .init(authorization: .denied, playbackEligibility: .unknown)
            }
        }

        await store.send(.submitButtonTapped) {
            $0.phase = .loading(requestID: UUID(0), stage: .checkingAccess)
        }
        await store.receive(\.currentAccessResponse)
        await store.receive(\.accessResolved) {
            $0.phase = .denied
        }
    }

    @Test
    func openSettingsOpensSystemSettingsURL() async {
        let opened = LockIsolated<[URL]>([])
        let store = TestStore(
            initialState: makeState(
                query: "",
                phase: .denied,
                playbackEligibility: .unknown
            )
        ) {
            SearchFeature()
        } withDependencies: {
            $0.openURL = OpenURLEffect { url in
                opened.withValue { $0.append(url) }
                return true
            }
        }

        await store.send(.openSettingsButtonTapped)
        await store.finish()

        #expect(opened.value.map(\.absoluteString) == [UIApplication.openSettingsURLString])
    }

    @Test
    func tappingLoadedResultDelegatesSelectedSong() async {
        let song = makeSong()
        let store = TestStore(
            initialState: makeState(
                query: "result",
                phase: .loaded([song]),
                playbackEligibility: .eligible
            )
        ) {
            SearchFeature()
        }

        await store.send(.resultTapped(song.id))
        await store.receive(.delegate(.songSelected(song)))
    }

    // MARK: - Helpers

    private func makeState(
        query: String,
        phase: SearchFeature.Phase,
        playbackEligibility: CatalogPlaybackEligibility
    ) -> SearchFeature.State {
        SearchFeature.State(
            query: query,
            phase: phase,
            playbackEligibility: playbackEligibility
        )
    }

    private func makeSong() -> SongSummary {
        SongSummary(
            id: .init(providerID: "fake", nativeID: "1"),
            title: "Result",
            artistName: "Artist",
            artworkURL: nil
        )
    }
}
