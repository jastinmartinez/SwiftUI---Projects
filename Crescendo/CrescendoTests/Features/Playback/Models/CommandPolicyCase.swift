import Testing

@testable import Crescendo

struct CommandPolicyCase: CustomTestStringConvertible {
    let name: String
    let command: PlaybackCommand
    let policy: PlaybackCommandPolicy
    let expected: Bool

    var testDescription: String { name }
}
