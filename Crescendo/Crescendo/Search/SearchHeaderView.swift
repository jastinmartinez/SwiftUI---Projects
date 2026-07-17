import SwiftUI

struct SearchHeaderView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let model: Model

    var body: some View {
        VStack(spacing: 16) {
            identity
            searchControls
        }
    }

    @ViewBuilder
    private var identity: some View {
        if dynamicTypeSize.isAccessibilitySize {
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
    private var searchControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                searchField
                searchButton
            }
        } else {
            HStack(spacing: 12) {
                searchField
                searchButton
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

    private var searchButton: some View {
        Button(action: model.onSubmit) {
            Text(Locs.Search.action)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(
                    maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil,
                    minHeight: 56
                )
                .background(
                    LinearGradient.crescendoSpectrum,
                    in: RoundedRectangle(cornerRadius: 18)
                )
        }
        .disabled(!model.isSearchEnabled)
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
