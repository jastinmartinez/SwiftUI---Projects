import Foundation

extension LibraryMediaStoreClient {
    /// Stores Library media under one managed root.
    ///
    /// This implementation coordinates the staged-copy lifecycle, content
    /// identification, durable promotion, managed-file enumeration, artwork
    /// storage, and opaque-reference resolution. Security-scoped access,
    /// filesystem containment, fingerprint mechanics, catalog persistence,
    /// metadata extraction, and import policy remain outside this adapter.
    ///
    /// - Parameters:
    ///   - fileSystem: The root-confined managed-file operations.
    ///   - securityScopedFileCopy: The external-file acquisition boundary used
    ///     during staging.
    /// - Returns: A reducer-facing managed-media client sharing those
    ///   infrastructure values.
    static func live(
        fileSystem: ManagedLibraryFileSystem,
        securityScopedFileCopy: SecurityScopedFileCopyClient
    ) -> Self {
        let mediaStore = LibraryMediaStore(
            fileSystem: fileSystem,
            securityScopedFileCopy: securityScopedFileCopy
        )
        return Self(
            stageAudio: { await mediaStore.stageAudio($0) },
            storeAudio: { await mediaStore.storeAudio($0, for: $1) },
            discardStagedAudio: { await mediaStore.discardStagedAudio($0) },
            listStoredAudio: { await mediaStore.listStoredAudio() },
            identifyAudio: { await mediaStore.identifyAudio($0) },
            storeArtwork: { await mediaStore.storeArtwork($0, for: $1) },
            resolveFileURL: { await mediaStore.resolveFileURL($0) }
        )
    }
}

private extension LibraryMediaStoreClient {
    struct LibraryMediaStore: Sendable {
        let fileSystem: ManagedLibraryFileSystem
        let securityScopedFileCopy: SecurityScopedFileCopyClient
        let fingerprinter = LibraryFileFingerprinter()

        func stageAudio(
            _ sourceURL: URL
        ) async -> Result<LibraryMediaStoreClient.StagedAudio, LibraryFailure> {
            let rawFileExtension = sourceURL.pathExtension.lowercased()
            guard
                !sourceURL.lastPathComponent.isEmpty,
                !rawFileExtension.isEmpty,
                rawFileExtension.unicodeScalars.allSatisfy(
                    CharacterSet.alphanumerics.contains
                )
            else {
                return .failure(.unsupportedFile)
            }

            let fileExtension = LibraryMediaStoreClient.FileExtension(
                rawValue: rawFileExtension
            )
            let temporaryURL = fileSystem.stagingDirectoryURL.appending(
                path: "\(UUID().uuidString).\(fileExtension.rawValue)"
            )

            do {
                try fileSystem.createDirectory(at: fileSystem.stagingDirectoryURL)
            } catch {
                return .failure(.fileWriteFailed)
            }

            return await withTaskCancellationHandler {
                switch await securityScopedFileCopy.copy(sourceURL, temporaryURL) {
                case .success:
                    break
                case let .failure(failure):
                    try? fileSystem.removeItemIfPresent(at: temporaryURL)
                    return .failure(failure)
                }

                guard !Task.isCancelled else {
                    try? fileSystem.removeItemIfPresent(at: temporaryURL)
                    return .failure(.fileReadFailed)
                }

                let contentIdentity: Library.ContentIdentity
                switch await fingerprinter.fingerprint(temporaryURL) {
                case let .success(identity):
                    contentIdentity = identity
                case let .failure(failure):
                    try? fileSystem.removeItemIfPresent(at: temporaryURL)
                    return .failure(failure)
                }

                guard !Task.isCancelled else {
                    try? fileSystem.removeItemIfPresent(at: temporaryURL)
                    return .failure(.fileReadFailed)
                }

                return .success(
                    LibraryMediaStoreClient.StagedAudio(
                        sourceName: sourceURL.lastPathComponent,
                        temporaryURL: temporaryURL,
                        fileExtension: fileExtension,
                        contentIdentity: contentIdentity
                    )
                )
            } onCancel: {
                try? fileSystem.removeItemIfPresent(at: temporaryURL)
            }
        }

        func storeAudio(
            _ stagedAudio: LibraryMediaStoreClient.StagedAudio,
            for trackID: TrackID
        ) async -> Result<LibraryMediaStoreClient.StoredAudio, LibraryFailure> {
            guard
                let reference = fileSystem.audioReference(
                    for: trackID,
                    fileExtension: stagedAudio.fileExtension
                ),
                let destinationURL = fileSystem.resolve(reference)
            else {
                return .failure(.invalidManagedFile)
            }

            do {
                try fileSystem.createDirectory(at: fileSystem.audioDirectoryURL)
                try fileSystem.moveItem(
                    from: stagedAudio.temporaryURL,
                    to: destinationURL
                )
                return try .success(
                    LibraryMediaStoreClient.StoredAudio(
                        trackID: trackID,
                        reference: reference,
                        url: destinationURL,
                        creationDate: fileSystem.creationDate(
                            at: destinationURL
                        )
                    )
                )
            } catch {
                return .failure(.fileWriteFailed)
            }
        }

        func discardStagedAudio(_ stagedAudio: LibraryMediaStoreClient.StagedAudio) async {
            try? fileSystem.removeItemIfPresent(at: stagedAudio.temporaryURL)
        }

        func listStoredAudio() async -> Result<[LibraryMediaStoreClient.StoredAudio], LibraryFailure> {
            do {
                try fileSystem.createDirectory(at: fileSystem.audioDirectoryURL)
                let fileURLs = try fileSystem.contentsOfDirectory(
                    at: fileSystem.audioDirectoryURL
                )
                var storedAudioFiles: [LibraryMediaStoreClient.StoredAudio] = []
                storedAudioFiles.reserveCapacity(fileURLs.count)

                for fileURL in fileURLs {
                    switch storedAudio(from: fileURL) {
                    case let .success(audio):
                        storedAudioFiles.append(audio)
                    case let .failure(failure):
                        return .failure(failure)
                    }
                }
                return .success(storedAudioFiles)
            } catch {
                return .failure(.fileReadFailed)
            }
        }

        func identifyAudio(_ fileURL: URL) async -> Result<Library.ContentIdentity, LibraryFailure> {
            await fingerprinter.fingerprint(fileURL)
        }

        func storeArtwork(
            _ data: Data,
            for trackID: TrackID
        ) async -> Result<LibraryMediaStoreClient.StoredArtwork, LibraryFailure> {
            guard
                let reference = fileSystem.artworkReference(for: trackID),
                let destinationURL = fileSystem.resolve(reference)
            else {
                return .failure(.invalidManagedFile)
            }

            do {
                try fileSystem.createDirectory(at: fileSystem.artworkDirectoryURL)
                try fileSystem.writeData(data, to: destinationURL)
                return .success(
                    LibraryMediaStoreClient.StoredArtwork(
                        reference: reference,
                        url: destinationURL
                    )
                )
            } catch {
                return .failure(.fileWriteFailed)
            }
        }

        func resolveFileURL(
            _ reference: LibraryMediaStoreClient.FileReference
        ) async -> Result<URL, LibraryFailure> {
            guard let fileURL = fileSystem.resolve(reference) else {
                return .failure(.invalidManagedFile)
            }
            return .success(fileURL)
        }

        private func storedAudio(
            from fileURL: URL
        ) -> Result<LibraryMediaStoreClient.StoredAudio, LibraryFailure> {
            let trackID = TrackID(
                providerID: .library,
                nativeID: fileURL.deletingPathExtension().lastPathComponent
            )
            let fileExtension = LibraryMediaStoreClient.FileExtension(
                rawValue: fileURL.pathExtension
            )
            guard
                let reference = fileSystem.audioReference(
                    for: trackID,
                    fileExtension: fileExtension
                ),
                let resolvedURL = fileSystem.resolve(reference)
            else {
                return .failure(.invalidManagedFile)
            }

            // FileManager may enumerate the app container through `/private/var`
            // even when its root was supplied through `/var`. Resolving both
            // paths preserves their file identity.
            let canonicalResolvedURL = resolvedURL.resolvingSymlinksInPath()
            let canonicalFileURL = fileURL.resolvingSymlinksInPath()
            guard canonicalResolvedURL == canonicalFileURL else {
                return .failure(.invalidManagedFile)
            }

            do {
                return try .success(
                    LibraryMediaStoreClient.StoredAudio(
                        trackID: trackID,
                        reference: reference,
                        url: fileURL,
                        creationDate: fileSystem.creationDate(at: fileURL)
                    )
                )
            } catch {
                return .failure(.fileReadFailed)
            }
        }
    }
}
