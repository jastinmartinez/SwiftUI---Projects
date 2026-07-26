extension ProviderAccessClient {
    static func live(jamendo configuration: JamendoConfiguration) -> Self {
        let access = MusicProviderAccess(
            authorization: .authorized,
            playbackEligibility: .eligible
        )
        return Self(
            currentAccess: { access },
            requestAccess: { access }
        )
    }
}
