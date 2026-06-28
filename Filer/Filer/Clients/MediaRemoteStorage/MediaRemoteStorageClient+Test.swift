import Dependencies

extension MediaRemoteStorageClient: TestDependencyKey {
    static let testValue = MediaRemoteStorageClient()
}

extension MediaRemoteStorageClient {
    static func mock(
        list: @escaping List = { [] },
        upload: @escaping Upload = { _ in AsyncThrowingStream { $0.finish() } },
        download: @escaping Download = { _ in AsyncThrowingStream { $0.finish() } }
    ) -> MediaRemoteStorageClient {
        let list = list
        let upload = upload
        let download = download

        return MediaRemoteStorageClient(
            list: list,
            upload: upload,
            download: download
        )
    }
}
