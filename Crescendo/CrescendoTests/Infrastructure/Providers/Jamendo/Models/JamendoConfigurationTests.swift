import Testing

@testable import Crescendo

struct JamendoConfigurationTests {
    @Test
    func trimsAConfiguredClientID() {
        let configuration = JamendoConfiguration(clientID: "  client-42  ")

        #expect(configuration?.clientID == "client-42")
    }

    @Test(arguments: [nil, "", "   "])
    func rejectsMissingClientID(_ value: String?) {
        #expect(JamendoConfiguration(clientID: value) == nil)
    }
}
