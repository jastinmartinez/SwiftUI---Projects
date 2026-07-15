import ComposableArchitecture
import Foundation
import Testing

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
                status: .idle,
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
            $0.status = .loading(requestID: UUID(0), stage: .checkingAccess)
        }
        await store.receive(\.currentAccessResponse)
        await store.receive(\.accessResolved) {
            $0.playbackEligibility = .eligible
            $0.status = .loading(requestID: UUID(0), stage: .searching)
        }
        await store.receive(\.searchResponse) {
            $0.status = .loaded([song])
        }
        #expect(accessCalls.value == ["current"])
    }

    @Test
    func ineligibleAccountStillReceivesSearchResults() async {
        let song = makeSong()
        let store = TestStore(
            initialState: makeState(
                query: "result",
                status: .idle,
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
            $0.status = .loading(requestID: UUID(0), stage: .checkingAccess)
        }
        await store.receive(\.currentAccessResponse)
        await store.receive(\.accessResolved) {
            $0.playbackEligibility = .ineligible
            $0.status = .loading(requestID: UUID(0), stage: .searching)
        }
        await store.receive(\.searchResponse) {
            $0.status = .loaded([song])
        }
    }

    @Test
    func undeterminedAccessIsRequestedBeforeSearch() async {
        let accessCalls = LockIsolated<[String]>([])
        let song = makeSong()
        let store = TestStore(
            initialState: makeState(
                query: "result",
                status: .idle,
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
            $0.status = .loading(requestID: UUID(0), stage: .checkingAccess)
        }
        await store.receive(\.currentAccessResponse) {
            $0.status = .loading(requestID: UUID(0), stage: .requestingAccess)
        }
        await store.receive(\.requestAccessResponse)
        await store.receive(\.accessResolved) {
            $0.playbackEligibility = .eligible
            $0.status = .loading(requestID: UUID(0), stage: .searching)
        }
        await store.receive(\.searchResponse) {
            $0.status = .loaded([song])
        }
        #expect(accessCalls.value == ["current", "request"])
    }

    @Test
    func staleResponseIsIgnored() async {
        let state = makeState(
            query: "new",
            status: .loading(requestID: UUID(2), stage: .searching),
            playbackEligibility: .unknown
        )
        let store = TestStore(initialState: state) { SearchFeature() }

        await store.send(.searchResponse(UUID(1), .success([])))
    }

    @Test
    func changingQueryInvalidatesLoadingSearch() async {
        let state = makeState(
            query: "old",
            status: .loading(requestID: UUID(0), stage: .checkingAccess),
            playbackEligibility: .unknown
        )
        let store = TestStore(initialState: state) { SearchFeature() }

        await store.send(.queryChanged("new")) {
            $0.query = "new"
            $0.status = .idle
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
                status: .idle,
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
            $0.status = .loading(requestID: UUID(0), stage: .checkingAccess)
        }
        await store.receive(\.currentAccessResponse)
        await store.receive(\.accessResolved) {
            $0.status = .denied
        }
    }

    // MARK: - Helpers

    private func makeState(
        query: String,
        status: SearchFeature.SearchStatus,
        playbackEligibility: CatalogPlaybackEligibility
    ) -> SearchFeature.State {
        SearchFeature.State(
            query: query,
            status: status,
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
