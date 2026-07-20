import SwiftUI

struct SearchHeaderView: View {
    let model: Model

    var body: some View {
        AccessibilityLayoutReader { layout in
            VStack(spacing: 16) {
                identity(layout: layout)
                searchControls(layout: layout)
            }
        }
    }

    @ViewBuilder
    private func identity(layout: AccessibilityLayout) -> some View {
        if layout == .expanded {
            VStack(alignment: .leading, spacing: 12) {
                title
                ProviderSelectionView(model: model.providerSelection)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .center) {
                title
                Spacer()
                ProviderSelectionView(model: model.providerSelection)
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
        Text(Locs.App.title)
            .font(.largeTitle.bold())
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(
                Locs.Search.prompt,
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
                .accessibilityLabel(Locs.Search.clear)
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
            Text(Locs.Search.action)
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
        let providerSelection: ProviderSelectionView.Model
        let isSearchEnabled: Bool
        let onQueryChanged: (String) -> Void
        let onSubmit: () -> Void
    }
}
