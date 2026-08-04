import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

struct NowPlayingImageClientLiveTests {
    @Test
    func successfulHTTPResponseReturnsData() async throws {
        let url = try #require(URL(string: "https://example.com/artwork.png"))
        let expectedData = Data([1, 2, 3])
        let response = try #require(
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )
        let receivedRequest = LockIsolated<URLRequest?>(nil)
        let client = NowPlayingImageClient.live(
            data: { request in
                receivedRequest.withValue { $0 = request }
                return (expectedData, response)
            }
        )

        let data = try await client.load(url)

        #expect(data == expectedData)
        #expect(receivedRequest.value?.url == url)
    }

    @Test
    func unsuccessfulHTTPResponseIsRejected() async throws {
        let url = try #require(URL(string: "https://example.com/missing.png"))
        let response = try #require(
            HTTPURLResponse(
                url: url,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )
        )
        let client = NowPlayingImageClient.live(
            data: { _ in (Data([1]), response) }
        )

        do {
            _ = try await client.load(url)
            Issue.record("expected an unsuccessful HTTP response to fail")
        } catch let error as URLError {
            #expect(error.code == .badServerResponse)
        } catch {
            Issue.record("expected URLError.badServerResponse, received \(error)")
        }
    }

    @Test
    func fileResponseReturnsData() async throws {
        let url = URL(fileURLWithPath: "/managed/artwork.png")
        let expectedData = Data([4, 5, 6])
        let response = URLResponse(
            url: url,
            mimeType: "image/png",
            expectedContentLength: expectedData.count,
            textEncodingName: nil
        )
        let client = NowPlayingImageClient.live(
            data: { _ in (expectedData, response) }
        )

        let data = try await client.load(url)

        #expect(data == expectedData)
    }
}
