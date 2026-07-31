import AVFoundation
import CoreVideo
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
    func assetWithoutAnAudioTrackIsUnsupported() async throws {
        let videoURL = try await makeVideoOnlyAsset()
        defer { try? FileManager.default.removeItem(at: videoURL) }
        let client = AudioMetadataClient.live()

        let result = await client.read(videoURL)

        #expect(result == .failure(.unsupportedFile))
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

    @MainActor
    private func makeVideoOnlyAsset() async throws -> URL {
        let fileURL = URL.temporaryDirectory.appending(
            path: "AudioMetadataClientLiveTests-video-\(UUID().uuidString).mov"
        )
        let writer = try AVAssetWriter(outputURL: fileURL, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 16,
                AVVideoHeightKey: 16,
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 16,
                kCVPixelBufferHeightKey as String: 16,
            ]
        )
        guard writer.canAdd(input) else { throw FixtureError.writerSetup }
        writer.add(input)
        guard writer.startWriting() else { throw FixtureError.writerSetup }
        writer.startSession(atSourceTime: .zero)

        var pixelBuffer: CVPixelBuffer?
        guard
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                16,
                16,
                kCVPixelFormatType_32BGRA,
                nil,
                &pixelBuffer
            ) == kCVReturnSuccess,
            let pixelBuffer,
            adaptor.append(pixelBuffer, withPresentationTime: .zero)
        else {
            throw FixtureError.writerSetup
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw FixtureError.writerSetup
        }
        return fileURL
    }
}

private final class FixtureBundleToken: NSObject {}

private enum FixtureError: Error {
    case writerSetup
}
