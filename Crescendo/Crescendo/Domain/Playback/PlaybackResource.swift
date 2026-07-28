import Foundation

/// A provider-resolved location that a playback engine can load for one track.
struct PlaybackResource: Equatable, Sendable {
    let trackID: TrackID
    let location: Location
}

extension PlaybackResource {
    enum Location: Equatable, Sendable {
        case localFile(URL)
        case progressive(URL)
        case hls(URL)

        var url: URL {
            switch self {
            case .localFile(let url),
                .progressive(let url),
                .hls(let url):
                return url
            }
        }
    }
}
