import Foundation

extension TimeInterval {
    var musicDurationText: String {
        let totalSeconds = max(0, Int(rounded(.down)))
        return String(
            format: "%d:%02d",
            totalSeconds / 60,
            totalSeconds % 60
        )
    }
}
