import Foundation

extension FileRowView {
    struct Model {
        let name: String
        let subtitle: String
        let accessory: FileRowAccessoryView.Model
        let send: (Action) -> Void
    }
}

extension FileRowView.Model {
    enum Action { case tapped, cancelTapped, retryTapped }
}
