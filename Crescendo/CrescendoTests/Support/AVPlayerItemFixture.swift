@preconcurrency import AVFoundation

enum AVPlayerItemFixture {
    @MainActor
    static func make(duration: TimeInterval = 1) -> AVPlayerItem {
        let composition = AVMutableComposition()
        composition.insertEmptyTimeRange(
            CMTimeRange(
                start: .zero,
                duration: CMTime(
                    seconds: max(0, duration),
                    preferredTimescale: 600
                )
            )
        )
        return AVPlayerItem(asset: composition)
    }
}
