import SwiftUI

/// Renders continuation progress and recovery without owning workflow state.
struct SearchPaginationFooterView: View {
    let model: Model

    var body: some View {
        switch model.content {
        case .hidden:
            EmptyView()

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
        let content: Content
        let strings: Strings
        let onRetry: () -> Void
    }
}

extension SearchPaginationFooterView.Model {
    enum Content: Equatable {
        case hidden
        case loading
        case failed
    }

    struct Strings: Equatable {
        let loading: String
        let failure: String
        let retry: String
    }
}
