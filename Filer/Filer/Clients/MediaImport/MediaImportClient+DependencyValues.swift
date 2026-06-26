import Dependencies

extension DependencyValues {
    var mediaImport: MediaImportClient {
        get { self[MediaImportClient.self] }
        set { self[MediaImportClient.self] = newValue }
    }
}
