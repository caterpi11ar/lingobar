import Foundation
import LingobarApplication

public final class UserDefaultsCredentialsStore: CredentialsStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let prefix: String

    public init(defaults: UserDefaults = .standard, prefix: String = "lingobar.credentials") {
        self.defaults = defaults
        self.prefix = prefix
    }

    public func apiKey(for providerID: String) async throws -> String? {
        defaults.string(forKey: storageKey(for: providerID))
    }

    public func saveAPIKey(_ apiKey: String?, for providerID: String) async throws {
        let key = storageKey(for: providerID)
        if let apiKey, !apiKey.isEmpty {
            defaults.set(apiKey, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func storageKey(for providerID: String) -> String {
        "\(prefix).\(providerID)"
    }
}
