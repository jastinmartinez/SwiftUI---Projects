import SwiftUI

struct SearchHeaderView: View {
    let model: Model

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center) {
                Text(Locs.App.title)
                    .font(.largeTitle.bold())
                Spacer()
                ProviderSelectionView(model: model.providerSelection)
            }

            HStack(spacing: 12) {
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

                Button(action: model.onSubmit) {
                    Text(Locs.Search.action)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 56)
                        .background(
                            LinearGradient.crescendoSpectrum,
                            in: RoundedRectangle(cornerRadius: 18)
                        )
                }
                .disabled(!model.isSearchEnabled)
            }
        }
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
