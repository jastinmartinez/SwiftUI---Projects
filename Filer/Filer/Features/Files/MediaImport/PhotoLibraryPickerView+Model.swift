import PhotosUI
import SwiftUI

extension PhotoLibraryPickerView {
    struct Model {
        let isLoading: Bool
        let send: (Action) -> Void
    }
}

extension PhotoLibraryPickerView.Model {
    enum Action { case picked([PhotosPickerItem]) }
}
