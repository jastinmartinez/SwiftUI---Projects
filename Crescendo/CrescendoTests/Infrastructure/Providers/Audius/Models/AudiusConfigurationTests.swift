import Testing

@testable import Crescendo

struct AudiusConfigurationTests {
    @Test
    func validKeyIsTrimmed() throws {
        let configuration = try #require(
            AudiusConfiguration(apiKey: "  public-key-42  ")
        )

        #expect(configuration.apiKey == "public-key-42")
    }

    @Test
    func missingOrBlankKeyIsRejected() {
        let values: [String?] = [nil, "", "   ", "\n\t"]

        for value in values {
            #expect(AudiusConfiguration(apiKey: value) == nil)
        }
    }
}
