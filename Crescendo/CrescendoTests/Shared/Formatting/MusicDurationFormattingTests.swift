import Foundation
import Testing

@testable import Crescendo

struct MusicDurationFormattingTests {
    @Test(arguments: [
        (value: 0.0, expected: "0:00"),
        (value: 65.9, expected: "1:05"),
        (value: -3.0, expected: "0:00"),
    ])
    func formatsPlaybackTime(value: TimeInterval, expected: String) {
        #expect(value.musicDurationText == expected)
    }
}
