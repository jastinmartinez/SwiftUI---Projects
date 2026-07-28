extension PlaybackItemClient {
    static func live(
        preparer: AVPlayerItemPreparer,
        installer: AVPlayerItemInstaller
    ) -> Self {
        Self(
            load: { resource, installation in
                let item = try await preparer.prepare(resource)
                try await installer.install(
                    item,
                    for: resource,
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
