import ComposableArchitecture

extension ProviderSelectionView.Model {
    @MainActor
    init(_ store: StoreOf<AppFeature>) {
        let state = store.providerConnection
        let status = Self.status(
            for: state.connection,
            providers: state.providers
        )
        let isSelectionEnabled =
            store.providerSwitch == nil
            && store.playbackStart == nil
            && !Self.isConnecting(status)

        self.init(
            status: status,
            collapsedIcon: Self.collapsedIcon(for: status),
            collapsedLabel: Self.collapsedLabel(for: status),
            menuTitle: Locs.ProviderSelection.menuTitle,
            providerRows: state.providers.map { provider in
                ProviderRow(
                    id: provider.id,
                    label: provider.name,
                    statusLabel: Self.statusLabel(for: status, provider: provider),
                    isSelected: Self.isSelected(provider: provider, status: status),
                    isEnabled: isSelectionEnabled,
                    onSelect: { store.send(.providerSelected(provider.id)) }
                )
            },
            recoveryAction: Self.recoveryAction(for: status, store: store),
            isSelectionEnabled: isSelectionEnabled
        )
    }

    // MARK: - Presentation

    private static func status(
        for connection: ProviderConnection,
        providers: [ProviderDescriptor]
    ) -> Status {
        func providerName(for providerID: ProviderID) -> String? {
            providers.first { $0.id == providerID }?.name
        }

        switch connection {
        case .disconnected:
            return .disconnected
        case .connecting(let providerID, _):
            return providerName(for: providerID).map(Status.connecting)
                ?? .disconnected
        case .connected(let providerID, _):
            return providerName(for: providerID).map(Status.connected)
                ?? .disconnected
        case .denied(let providerID):
            return providerName(for: providerID).map(Status.needsAccess)
                ?? .disconnected
        case .restricted(let providerID):
            return providerName(for: providerID).map(Status.restricted)
                ?? .disconnected
        case .failed(let providerID):
            return providerName(for: providerID).map(Status.failed)
                ?? .disconnected
        }
    }

    private static func collapsedIcon(for status: Status) -> Icon {
        switch status {
        case .disconnected:
            .generic
        case .connecting, .connected, .needsAccess, .restricted, .failed:
            .appleMusic
        }
    }

    private static func collapsedLabel(for status: Status) -> String {
        switch status {
        case .disconnected:
            Locs.ProviderSelection.connect
        case .connecting(let providerName):
            Locs.ProviderSelection.connectingTo(providerName)
        case .connected(let providerName):
            providerName
        case .needsAccess(let providerName):
            Locs.ProviderSelection.needsAccess(providerName)
        case .restricted(let providerName):
            Locs.ProviderSelection.restricted(providerName)
        case .failed(let providerName):
            Locs.ProviderSelection.connectionFailed(providerName)
        }
    }

    private static func statusLabel(
        for status: Status,
        provider: ProviderDescriptor
    ) -> String? {
        switch status {
        case .connecting(let providerName) where provider.name == providerName:
            Locs.ProviderSelection.connecting
        case .needsAccess(let providerName) where provider.name == providerName:
            Locs.ProviderSelection.needsAccessIndicator
        case .restricted(let providerName) where provider.name == providerName:
            Locs.ProviderSelection.restrictedIndicator
        case .failed(let providerName) where provider.name == providerName:
            Locs.ProviderSelection.connectionFailedIndicator
        case .disconnected, .connected, .connecting, .needsAccess, .restricted,
            .failed:
            nil
        }
    }

    private static func isSelected(
        provider: ProviderDescriptor,
        status: Status
    ) -> Bool {
        guard case .connected(let providerName) = status else { return false }
        return provider.name == providerName
    }

    private static func recoveryAction(
        for status: Status,
        store: StoreOf<AppFeature>
    ) -> RecoveryAction? {
        switch status {
        case .needsAccess:
            RecoveryAction(
                label: Locs.ProviderSelection.openSettings,
                perform: {
                    store.send(.providerConnection(.openSettingsButtonTapped))
                }
            )
        case .failed:
            RecoveryAction(
                label: Locs.ProviderSelection.tryAgain,
                perform: {
                    store.send(.providerConnection(.retryButtonTapped))
                }
            )
        case .disconnected, .connecting, .connected, .restricted:
            nil
        }
    }

    private static func isConnecting(_ status: Status) -> Bool {
        guard case .connecting = status else { return false }
        return true
    }
}
