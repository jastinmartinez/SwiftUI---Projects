import ComposableArchitecture
import Foundation
import IdentifiedCollections
import Testing

@testable import Crescendo

struct LibraryClientContractTests {
    @Test
    func mediaStoreRequiresExplicitOperationsAndPreservesTheirResults() async {
        let sourceURL = URL(fileURLWithPath: "/external/song.m4a")
        let stagedAudio = LibraryMediaStoreClient.StagedAudio(
            sourceName: "song.m4a",
            temporaryURL: URL(fileURLWithPath: "/staging/song.m4a"),
            fileExtension: .init(rawValue: "m4a"),
            contentIdentity: .init(rawValue: "content")
        )
        let trackID = TrackID(providerID: .library, nativeID: "track")
        let storedAudio = LibraryMediaStoreClient.StoredAudio(
            trackID: trackID,
            reference: .init(rawValue: "Audio/track.m4a"),
            url: URL(fileURLWithPath: "/library/Audio/track.m4a"),
            creationDate: Date(timeIntervalSinceReferenceDate: 100)
        )
        let artworkData = Data([0xCA, 0xFE])
        let storedArtwork = LibraryMediaStoreClient.StoredArtwork(
            reference: .init(rawValue: "Artwork/track.jpg"),
            url: URL(fileURLWithPath: "/library/Artwork/track.jpg")
        )
        let unresolvedReference = LibraryMediaStoreClient.FileReference(
            rawValue: "outside-library"
        )
        let stageURLs = LockIsolated<[URL]>([])
        let storedStages = LockIsolated<[LibraryMediaStoreClient.StagedAudio]>([])
        let storedTrackIDs = LockIsolated<[TrackID]>([])
        let discardedStages = LockIsolated<[LibraryMediaStoreClient.StagedAudio]>([])
        let listCallCount = LockIsolated(0)
        let identifiedURLs = LockIsolated<[URL]>([])
        let artworkPayloads = LockIsolated<[Data]>([])
        let artworkTrackIDs = LockIsolated<[TrackID]>([])
        let resolvedReferences = LockIsolated<[LibraryMediaStoreClient.FileReference]>([])
        let client = LibraryMediaStoreClient(
            stageAudio: { url in
                stageURLs.withValue { $0.append(url) }
                return .success(stagedAudio)
            },
            storeAudio: { staged, trackID in
                storedStages.withValue { $0.append(staged) }
                storedTrackIDs.withValue { $0.append(trackID) }
                return .failure(.fileWriteFailed)
            },
            discardStagedAudio: { staged in
                discardedStages.withValue { $0.append(staged) }
            },
            listStoredAudio: {
                listCallCount.withValue { $0 += 1 }
                return .success([storedAudio])
            },
            identifyAudio: { url in
                identifiedURLs.withValue { $0.append(url) }
                return .failure(.fileReadFailed)
            },
            storeArtwork: { data, trackID in
                artworkPayloads.withValue { $0.append(data) }
                artworkTrackIDs.withValue { $0.append(trackID) }
                return .success(storedArtwork)
            },
            resolveFileURL: { reference in
                resolvedReferences.withValue { $0.append(reference) }
                return .failure(.invalidManagedFile)
            }
        )

        let stageResult = await client.stageAudio(sourceURL)
        let storeResult = await client.storeAudio(stagedAudio, trackID)
        await client.discardStagedAudio(stagedAudio)
        let listResult = await client.listStoredAudio()
        let identityResult = await client.identifyAudio(sourceURL)
        let artworkResult = await client.storeArtwork(artworkData, trackID)
        let resolutionResult = await client.resolveFileURL(
            unresolvedReference
        )

        #expect(stageURLs.value == [sourceURL])
        #expect(stageResult == .success(stagedAudio))
        #expect(storedStages.value == [stagedAudio])
        #expect(storedTrackIDs.value == [trackID])
        #expect(storeResult == .failure(.fileWriteFailed))
        #expect(discardedStages.value == [stagedAudio])
        #expect(listCallCount.value == 1)
        #expect(listResult == .success([storedAudio]))
        #expect(identifiedURLs.value == [sourceURL])
        #expect(identityResult == .failure(.fileReadFailed))
        #expect(artworkPayloads.value == [artworkData])
        #expect(artworkTrackIDs.value == [trackID])
        #expect(artworkResult == .success(storedArtwork))
        #expect(resolvedReferences.value == [unresolvedReference])
        #expect(resolutionResult == .failure(.invalidManagedFile))
    }

    @Test
    func metadataRequiresAnExplicitReadOperationAndPreservesResults() async {
        let readableURL = URL(fileURLWithPath: "/external/readable.m4a")
        let unreadableURL = URL(fileURLWithPath: "/external/unreadable.m4a")
        let metadata = AudioMetadataClient.Metadata(
            title: "Song",
            artistName: "Artist",
            albumTitle: "Album",
            albumArtistName: "Album Artist",
            duration: 180,
            trackNumber: 2,
            discNumber: 1,
            artworkData: Data([0x01, 0x02])
        )
        let readURLs = LockIsolated<[URL]>([])
        let client = AudioMetadataClient(
            read: { url in
                readURLs.withValue { $0.append(url) }
                guard url == readableURL else {
                    return .failure(.metadataReadFailed)
                }
                return .success(metadata)
            }
        )

        let success = await client.read(readableURL)
        let failure = await client.read(unreadableURL)

        #expect(readURLs.value == [readableURL, unreadableURL])
        #expect(success == .success(metadata))
        #expect(failure == .failure(.metadataReadFailed))
    }

    @Test
    func catalogRequiresExplicitOperationsAndPreservesTheirResults() async {
        let entry = LibraryCatalogClient.Entry(
            id: TrackID(providerID: .library, nativeID: "track"),
            audioReference: .init(rawValue: "Audio/track.m4a"),
            contentIdentity: .init(rawValue: "content"),
            title: "Song",
            artistName: "Artist",
            albumTitle: "Album",
            albumArtistName: "Album Artist",
            duration: 180,
            trackNumber: 2,
            discNumber: 1,
            artworkReference: .init(rawValue: "Artwork/track.jpg"),
            addedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        let snapshot = LibraryCatalogClient.Snapshot(
            entries: IdentifiedArray(uniqueElements: [entry])
        )
        let loadCallCount = LockIsolated(0)
        let replacementSnapshots = LockIsolated<[LibraryCatalogClient.Snapshot]>([])
        let client = LibraryCatalogClient(
            load: {
                loadCallCount.withValue { $0 += 1 }
                return .success(snapshot)
            },
            replace: { replacement in
                replacementSnapshots.withValue { $0.append(replacement) }
                return .failure(.catalogWriteFailed)
            }
        )

        let loadResult = await client.load()
        let replaceResult = await client.replace(snapshot)

        #expect(loadCallCount.value == 1)
        #expect(loadResult == .success(snapshot))
        #expect(replacementSnapshots.value == [snapshot])
        #expect(replaceResult == .failure(.catalogWriteFailed))
    }
}
