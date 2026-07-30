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
        static let loadingMore = String(localized: "search.loading_more")
        static let loadMoreFailed = String(localized: "search.load_more_failed")
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

    enum Playback {
        static let noSelection = String(localized: "music_playback.no_selection")
        static let play = String(localized: "music_playback.play")
        static let pause = String(localized: "music_playback.pause")
        static let dismiss = String(localized: "music_playback.dismiss")
        static let previous = String(localized: "music_playback.previous")
        static let next = String(localized: "music_playback.next")
        static let shuffle = String(localized: "music_playback.shuffle")
        static let repeatMode = String(localized: "music_playback.repeat")
        static let position = String(localized: "music_playback.position")
        static let stop = String(localized: "music_playback.stop")
        static let restart = String(localized: "music_playback.restart")
        static let backwardFifteenSeconds = String(
            localized: "music_playback.backward_fifteen_seconds"
        )
        static let forwardFifteenSeconds = String(
            localized: "music_playback.forward_fifteen_seconds"
        )
        static let upNext = String(localized: "music_playback.up_next")

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

        enum Mode {
            static let off = String(localized: "music_playback.mode.off")
            static let on = String(localized: "music_playback.mode.on")
            static let all = String(localized: "music_playback.mode.all")
            static let one = String(localized: "music_playback.mode.one")
        }

        enum Status {
            static let idle = String(localized: "music_playback.status.idle")
            static let loading = String(localized: "music_playback.status.loading")
            static let waiting = String(localized: "music_playback.status.waiting")
            static let playing = String(localized: "music_playback.status.playing")
            static let paused = String(localized: "music_playback.status.paused")
            static let stopped = String(localized: "music_playback.status.stopped")
        }

        enum Failure {
            static let resourceUnavailable = String(
                localized: "music_playback.failure.resource_unavailable"
            )
            static let unsupportedResource = String(
                localized: "music_playback.failure.unsupported_resource"
            )
            static let preparationFailed = String(
                localized: "music_playback.failure.preparation_failed"
            )
            static let playbackFailed = String(
                localized: "music_playback.failure.playback_failed"
            )
        }
    }
}
