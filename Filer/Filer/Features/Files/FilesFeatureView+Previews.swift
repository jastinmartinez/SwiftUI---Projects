import ComposableArchitecture
import SwiftUI

#Preview("Ready") {
    FilesFeatureView(store: Store(
        initialState: FilesFeature.State(
            files: IdentifiedArray(uniqueElements: [
                FileFeature.State(item: FileItem(id: "1.jpg", name: "Sunset", kind: .image, size: 2_400_000, status: .remote)),
                FileFeature.State(item: FileItem(id: "2.mov", name: "Clip", kind: .video, size: 12_000_000, status: .local(URL(filePath: "/tmp/2.mov")))),
            ], id: \.item.id),
            loadPhase: .ready
        )
    ) { FilesFeature() })
}

#Preview("Empty") {
    FilesFeatureView(store: Store(
        initialState: FilesFeature.State(loadPhase: .ready)
    ) { FilesFeature() })
}

#Preview("Loading") {
    FilesFeatureView(store: Store(
        initialState: FilesFeature.State(loadPhase: .loading)
    ) { FilesFeature() })
}

#Preview("Failed") {
    FilesFeatureView(store: Store(
        initialState: FilesFeature.State(loadPhase: .failed("The network connection was lost."))
    ) { FilesFeature() })
}
