/// A provider-neutral playback-speed multiplier.
struct PlaybackRate: Equatable, Sendable {
    let value: Float
}

extension PlaybackRate {
    static let half = Self(value: 0.5)
    static let normal = Self(value: 1)
    static let oneAndQuarter = Self(value: 1.25)
    static let oneAndHalf = Self(value: 1.5)
    static let double = Self(value: 2)
}
