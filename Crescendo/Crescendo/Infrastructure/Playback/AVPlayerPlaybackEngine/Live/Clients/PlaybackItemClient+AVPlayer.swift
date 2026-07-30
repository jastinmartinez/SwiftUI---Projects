extension PlaybackItemClient {
    static func live(
        preparer: AVPlayerItemPreparer,
        installer: AVPlayerItemInstaller
    ) -> Self {
        Self(
            load: { trackID, playbackURL, installation in
                let item = try await preparer.prepare(playbackURL)
                try await installer.install(
                    item,
                    trackID: trackID,
                    installation: installation
                )
            },
            commit: { installation in
                await installer.commit(installation)
            },
            rollback: { installation in
                await installer.rollback(installation)
            }
        )
    }
}
