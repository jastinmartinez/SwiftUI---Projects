import Foundation

extension FilesErrorView {
    struct Model {
        let message: String
        let send: (Action) -> Void
    }
}

extension FilesErrorView.Model {
    enum Action { case retryTapped }
}
