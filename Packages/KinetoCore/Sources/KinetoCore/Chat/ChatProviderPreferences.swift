import Foundation

/// UserDefaults-backed chat provider selection and egress consent.
/// Secrets never live here — only provider IDs and consent flags.
public enum ChatProviderPreferences {
    public static let defaultProviderKey = "kineto.chat.defaultProvider"
    public static let alwaysAskKey = "kineto.chat.alwaysAskBeforeEgress"
    private static let consentPrefix = "kineto.chat.egressConsent."

    public static func defaultProvider(
        defaults: UserDefaults = .standard
    ) -> ChatProviderID {
        guard let raw = defaults.string(forKey: defaultProviderKey),
              let provider = ChatProviderID(rawValue: raw) else {
            return .appleOnDevice
        }
        return provider
    }

    public static func setDefaultProvider(
        _ provider: ChatProviderID,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(provider.rawValue, forKey: defaultProviderKey)
    }

    public static func alwaysAskBeforeEgress(
        defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.object(forKey: alwaysAskKey) as? Bool ?? false
    }

    public static func setAlwaysAskBeforeEgress(
        _ value: Bool,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(value, forKey: alwaysAskKey)
    }

    public static func hasConsented(
        to provider: ChatProviderID,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard provider.sendsMeetingExcerptsOffDevice else { return true }
        return defaults.bool(forKey: consentKey(for: provider))
    }

    public static func setConsented(
        _ consented: Bool,
        to provider: ChatProviderID,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(consented, forKey: consentKey(for: provider))
    }

    public static func shouldRequestConsent(
        for provider: ChatProviderID,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard provider.sendsMeetingExcerptsOffDevice else { return false }
        if alwaysAskBeforeEgress(defaults: defaults) { return true }
        return !hasConsented(to: provider, defaults: defaults)
    }

    public static func consentDisclosure(for provider: ChatProviderID) -> String {
        "This question and the retrieved transcript excerpts will be sent to \(provider.displayName). The full meeting, audio, and encryption keys stay on this Mac."
    }

    private static func consentKey(for provider: ChatProviderID) -> String {
        consentPrefix + provider.rawValue
    }
}
