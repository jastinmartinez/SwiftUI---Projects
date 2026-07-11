import Foundation

extension FileRowView {
    struct Model {
        let name: String
        let subtitle: String
        let accessory: FileRowAccessoryView.Model
        let trailingOperation: TrailingOperation?
        let onTap: () -> Void

        init(
            name: String,
            subtitle: String,
            accessory: FileRowAccessoryView.Model,
            trailingOperation: TrailingOperation? = nil,
            onTap: @escaping () -> Void
        ) {
            self.name = name
            self.subtitle = subtitle
            self.accessory = accessory
            self.trailingOperation = trailingOperation
            self.onTap = onTap
        }
    }
}

extension FileRowView.Model {
    struct TrailingOperation {
        let kind: Kind
        let perform: () -> Void
    }
}

extension FileRowView.Model.TrailingOperation {
    enum Kind: Hashable { case cancel, retry }
}
