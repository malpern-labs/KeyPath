import KeyPathRulesCore

extension ConfigurationService {
    /// In-app generation can use the current preference while the UI is staging a change.
    static func forApp(configDirectory: String? = nil) -> ConfigurationService {
        ConfigurationService(
            configDirectory: configDirectory,
            fallbackLeaderPreference: { PreferencesService.shared.leaderKeyPreference }
        )
    }
}
