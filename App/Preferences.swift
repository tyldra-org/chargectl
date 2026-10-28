import AppKit
import Foundation

enum PreferenceKey {
    static let showInMenuBar = "showInMenuBar"
    static let showPercentage = "showPercentage"
    static let temperatureUnit = "temperatureUnit"
    static let appearance = "appearance"
    static let setupComplete = "setupComplete"
    /// On unless turned off in Settings.
    static let autoUpdate = "autoUpdate"
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }
    var title: String { rawValue.capitalized }

    /// nil follows the system.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    static var current: AppearanceMode {
        UserDefaults.standard.string(forKey: PreferenceKey.appearance).flatMap(AppearanceMode.init) ?? .system
    }

    func apply() {
        NSApp.appearance = nsAppearance
    }
}

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius
    case fahrenheit

    static var systemDefault: TemperatureUnit {
        Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }

    var id: Self { self }
    var symbol: String { self == .celsius ? "°C" : "°F" }

    func value(_ celsius: Double) -> Double {
        self == .celsius ? celsius : celsius * 9 / 5 + 32
    }

    func format(_ celsius: Double?, decimals: Int = 1) -> String {
        guard let celsius else { return "–" }
        return String(format: "%.\(decimals)f %@", value(celsius), symbol)
    }
}

enum Format {
    static func watts(_ watts: Double?) -> String {
        guard let watts else { return "–" }
        return String(format: "%.1f W", watts)
    }

    static func signedWatts(_ watts: Double) -> String {
        String(format: "%+.1f W", watts)
    }

    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return "–" }
        return String(format: "%.1f%%", fraction * 100)
    }
}
