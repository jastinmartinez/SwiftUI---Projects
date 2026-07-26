extension ProviderAccessClient {
    static func live(appleMusic provider: AppleMusicProvider) -> Self {
        Self(
            currentAccess: { await provider.currentAccess() },
            requestAccess: { await provider.requestAccess() }
        )
    }
}
