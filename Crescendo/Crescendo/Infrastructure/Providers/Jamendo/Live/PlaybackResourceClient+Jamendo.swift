import Foundation

extension PlaybackResourceClient {
    static func live(jamendo api: JamendoAPI) -> Self {
        Self(
            resolve: { trackID in
                do {
                    let jamendoTrack = try await api.track(
                        id: trackID.nativeID
                    )
                    guard
                        let audioURL = URL(
                            httpString: jamendoTrack.audio
                        )
                    else {
                        throw PlaybackFailure.resourceUnavailable
                    }
                    return PlaybackResource(
                        trackID: trackID,
                        location: .progressive(audioURL)
                    )
                } catch let failure as PlaybackFailure {
                    throw failure
                } catch {
                    throw PlaybackFailure.resourceUnavailable
                }
            }
        )
    }
}
