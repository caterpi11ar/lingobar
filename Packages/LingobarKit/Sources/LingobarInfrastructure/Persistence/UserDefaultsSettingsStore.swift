import Foundation
import LingobarApplication
import LingobarDomain

public final class UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard, key: String = "lingobar.settings") {
        self.defaults = defaults
        self.key = key
    }

    public func load() async throws -> AppSettings {
        guard let data = defaults.data(forKey: key) else {
            return .default
        }
        return try decoder.decode(AppSettings.self, from: data)
    }

    public func save(_ settings: AppSettings) async throws {
        let data = try encoder.encode(settings)
        defaults.set(data, forKey: key)
    }
}
