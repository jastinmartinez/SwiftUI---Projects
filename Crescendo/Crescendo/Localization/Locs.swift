import Foundation

/// Typed access to every user-facing string. Nested enums mirror features;
/// keys resolve through Localizable.xcstrings.
enum Locs {
    enum App {
        static let title = String(localized: "app.title")
    }
}

extension Locs {
    enum Common {
        static let retry = String(localized: "common.retry")
    }

    enum Search {
        static let prompt = String(localized: "search.prompt")
        static let emptyTitle = String(localized: "search.empty_title")
        static let searching = String(localized: "search.searching")
        static let unavailableTitle = String(localized: "search.unavailable_title")
        static let videoStillAvailable = String(localized: "search.video_still_available")
    }

    enum MusicAccess {
        static let subscriptionRequired = String(
            localized: "music_access.subscription_required"
        )
        static let availabilityUnknown = String(
            localized: "music_access.availability_unknown"
        )
    }

    enum MusicPlayback {
        static let noSelection = String(localized: "music_playback.no_selection")
        static let play = String(localized: "music_playback.play")
        static let pause = String(localized: "music_playback.pause")
        static let stop = String(localized: "music_playback.stop")

        enum Status {
            static let idle = String(localized: "music_playback.status.idle")
            static let loading = String(localized: "music_playback.status.loading")
            static let playing = String(localized: "music_playback.status.playing")
            static let paused = String(localized: "music_playback.status.paused")
            static let stopped = String(localized: "music_playback.status.stopped")
            static let failed = String(localized: "music_playback.status.failed")
        }
    }
}
