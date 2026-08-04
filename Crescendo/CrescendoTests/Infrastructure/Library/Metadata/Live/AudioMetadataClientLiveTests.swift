import Foundation
import Testing

@testable import Crescendo

/// Proves AVFoundation metadata extraction without catalog or import workflow.
struct AudioMetadataClientLiveTests {
    @Test
    func supportedAudioReturnsKnownMetadataAndDuration() async throws {
        let sourceURL = try fixtureURL()
        let client = AudioMetadataClient.live()

        let metadata = try await client.read(sourceURL).get()

        #expect(metadata.title == "Fixture Song")
        #expect(metadata.artistName == "Fixture Artist")
        #expect(metadata.albumTitle == "Fixture Album")
        #expect(metadata.albumArtistName == "Fixture Album Artist")
        #expect(try abs(#require(metadata.duration) - 0.5) < 0.05)
        #expect(metadata.trackNumber == 2)
        #expect(metadata.discNumber == 1)
    }

    @Test
    func corruptAudioMapsToMetadataReadFailure() async throws {
        let sourceURL = URL.temporaryDirectory.appending(
            path: "AudioMetadataClientLiveTests-corrupt-\(UUID().uuidString).m4a"
        )
        try Data("not audio".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let client = AudioMetadataClient.live()

        let result = await client.read(sourceURL)

        #expect(result == .failure(.metadataReadFailed))
    }

    @Test
    func metadataReadDoesNotMoveOrPersistTheSource() async throws {
        let rootURL = URL.temporaryDirectory.appending(
            path: "AudioMetadataClientLiveTests-read-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let sourceURL = rootURL.appending(path: "source.m4a")
        let sourceData = try Data(contentsOf: fixtureURL())
        try sourceData.write(to: sourceURL)
        let client = AudioMetadataClient.live()

        _ = await client.read(sourceURL)

        #expect(try Data(contentsOf: sourceURL) == sourceData)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: rootURL.path)
                == ["source.m4a"]
        )
    }

    private func fixtureURL() throws -> URL {
        let bundle = Bundle(for: FixtureBundleToken.self)
        return try #require(
            bundle.url(
                forResource: "library-metadata-fixture",
                withExtension: "m4a"
            )
                ?? bundle.url(
                    forResource: "library-metadata-fixture",
                    withExtension: "m4a",
                    subdirectory: "Fixtures/Audio"
                )
        )
    }
}

private final class FixtureBundleToken: NSObject {}
