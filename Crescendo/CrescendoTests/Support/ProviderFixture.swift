@testable import Crescendo

extension ProviderID {
    static let testProvider = Self(rawValue: "test-provider")
}

extension ProviderDescriptor {
    static let testProvider = Self(
        id: .testProvider,
        name: "Test Provider",
        musicCapabilities: .allEnabled
    )
}
