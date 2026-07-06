import Dependencies
import Foundation
import Storage

extension MediaRemoteClient: DependencyKey {
    static var liveValue: MediaRemoteClient {
        live(config: .loadFromBundle())
    }

    static func live(config: SupabaseConfig) -> MediaRemoteClient {
        let storageURL = config.projectURL.appending(path: "storage/v1")
        let headers = SupabaseStorageHeaders.auth(config: config)
        let storage = SupabaseStorageClient(
            configuration: StorageClientConfiguration(
                url: storageURL,
                headers: headers,
                logger: nil
            )
        )

        let list: List = {
            try await storage.from(config.bucket).list().compactMap(FileItem.init)
        }
        let uploadRequest: UploadRequestFor = { media in
            SupabaseUpload.request(for: media, config: config)
        }
        let downloadRequest: DownloadRequestFor = { file in
            let url = try storage.from(config.bucket).getPublicURL(path: file.id)
            return DownloadRequest(
                url: url,
                headers: SupabaseStorageHeaders.download(config: config)
            )
        }

        return MediaRemoteClient(
            list: list,
            uploadRequest: uploadRequest,
            downloadRequest: downloadRequest
        )
    }
}
