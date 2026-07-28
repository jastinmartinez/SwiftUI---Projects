import SwiftUI

struct SearchHeaderView: View {
    let model: Model

    var body: some View {
        AccessibilityLayoutReaderView { layout in
            VStack(spacing: 16) {
                title
                    .frame(maxWidth: .infinity, alignment: .leading)
                searchControls(layout: layout)
            }
        }
    }

    @ViewBuilder
    private func searchControls(layout: AccessibilityLayout) -> some View {
        if layout == .expanded {
            VStack(spacing: 12) {
                searchField
                searchButton(layout: layout)
            }
        } else {
            HStack(spacing: 12) {
                searchField
                searchButton(layout: layout)
            }
        }
    }

    private var title: some View {
        Text(model.strings.title)
            .font(.largeTitle.bold())
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(
                model.strings.prompt,
                text: Binding(
                    get: { model.query },
                    set: { model.onQueryChanged($0) }
                )
            )
            .submitLabel(.search)
            .onSubmit(model.onSubmit)

            if !model.query.isEmpty {
                Button {
                    model.onQueryChanged("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(model.strings.clear)
            }
        }
        .padding(.leading, 16)
        .frame(minHeight: 56)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18)
        )
    }

    private func searchButton(layout: AccessibilityLayout) -> some View {
        Button(action: model.onSubmit) {
            Text(model.strings.action)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(
                    maxWidth: layout == .expanded ? .infinity : nil,
                    minHeight: 56
                )
                .background(
                    LinearGradient.crescendoSpectrum,
                    in: RoundedRectangle(cornerRadius: 18)
                )
        }
        .disabled(!model.isSearchEnabled)
        .opacity(model.isSearchEnabled ? 1 : 0.45)
    }
}

extension SearchHeaderView {
    struct Model {
        let query: String
        let isSearchEnabled: Bool
        let strings: Strings
        let onQueryChanged: (String) -> Void
        let onSubmit: () -> Void
    }
}

extension SearchHeaderView.Model {
    /// Contains every localized string rendered by the search header.
    struct Strings {
        let title: String
        let prompt: String
        let clear: String
        let action: String
    }
}
