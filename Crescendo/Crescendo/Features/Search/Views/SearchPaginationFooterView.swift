import SwiftUI

/// Renders continuation progress and recovery without owning workflow state.
struct SearchPaginationFooterView: View {
    let model: Model

    var body: some View {
        switch model.content {
        case .hidden:
            EmptyView()

        case .ready(let triggerID):
            Color.clear
                .frame(height: 1)
                .task(id: triggerID) {
                    model.onLoadNextPage()
                }

        case .loading:
            ProgressView(model.strings.loading)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)

        case .failed:
            VStack(spacing: 8) {
                Text(model.strings.failure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(model.strings.retry, action: model.onRetry)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }
}

extension SearchPaginationFooterView {
    struct Model {
        enum Content: Equatable {
            case hidden
            case ready(triggerID: String)
            case loading
            case failed
        }

        struct Strings: Equatable {
            let loading: String
            let failure: String
            let retry: String
        }

        let content: Content
        let strings: Strings
        let onLoadNextPage: () -> Void
        let onRetry: () -> Void
    }
}
