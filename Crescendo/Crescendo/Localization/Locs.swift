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
        static let action = String(localized: "search.action")
        static let clear = String(localized: "search.clear")
        static let prompt = String(localized: "search.prompt")
        static let emptyTitle = String(localized: "search.empty_title")
        static let searching = String(localized: "search.searching")
        static let deniedTitle = String(localized: "search.denied_title")
        static let deniedMessage = String(localized: "search.denied_message")
        static let openSettings = String(localized: "search.open_settings")
        static let restrictedTitle = String(localized: "search.restricted_title")
        static let restrictedMessage = String(localized: "search.restricted_message")

        static func resultsSummary(
            count: Int,
            providerName: String?
        ) -> String {
            let countFormat =
                count == 1
                ? String(localized: "search.result_count")
                : String(localized: "search.results_count")
            let countText = String(format: countFormat, Int64(count))
            guard let providerName else { return countText }
            return String(
                format: String(localized: "search.results_provider"),
                countText,
                providerName
            )
        }
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
        static let position = String(localized: "music_playback.position")
        static let stop = String(localized: "music_playback.stop")

        static func positionValue(
            elapsedTime: String,
            durationTime: String
        ) -> String {
            String(
                format: String(localized: "music_playback.position_value"),
                elapsedTime,
                durationTime
            )
        }

        static func playingFrom(_ providerName: String) -> String {
            String(
                format: String(localized: "music_playback.playing_from"),
                providerName
            )
        }

        enum Status {
            static let idle = String(localized: "music_playback.status.idle")
            static let loading = String(localized: "music_playback.status.loading")
            static let playing = String(localized: "music_playback.status.playing")
            static let paused = String(localized: "music_playback.status.paused")
            static let stopped = String(localized: "music_playback.status.stopped")
            static let failed = String(localized: "music_playback.status.failed")
            static let unavailable = String(localized: "music_playback.status.unavailable")
        }
    }

    enum ProviderSelection {
        static let title = String(localized: "provider_selection.title")
        static let noActiveProvider = String(
            localized: "provider_selection.no_active_provider"
        )
    }
}
