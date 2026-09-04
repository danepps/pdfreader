import AppKit

extension Notification.Name {
    static let folioPrefsChanged = Notification.Name("FolioPrefsChanged")
}

enum AppearanceMode: Int {
    case system = 0, light = 1, dark = 2

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// User preferences. Small on purpose; everything defaults to "follow the system".
enum Prefs {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let invertInDarkMode = "invertInDarkMode"
        static let appearance = "appearance"
        static let lastPositions = "lastPositions"
    }

    /// Render page content light-on-dark when the app is in dark mode. Default on.
    static var invertInDarkMode: Bool {
        get { defaults.object(forKey: Key.invertInDarkMode) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: Key.invertInDarkMode)
            NotificationCenter.default.post(name: .folioPrefsChanged, object: nil)
        }
    }

    /// System / Light / Dark override. Default follows the system.
    static var appearance: AppearanceMode {
        get { AppearanceMode(rawValue: defaults.integer(forKey: Key.appearance)) ?? .system }
        set {
            defaults.set(newValue.rawValue, forKey: Key.appearance)
            NSApp.appearance = newValue.nsAppearance
            NotificationCenter.default.post(name: .folioPrefsChanged, object: nil)
        }
    }

    // MARK: Reading position memory (per file path)

    struct Position {
        var pageIndex: Int
        var x: CGFloat
        var y: CGFloat
    }

    /// Entries are `[page, x, y, lastAccessed]`; older three-element entries
    /// still read (and are treated as least recently used).
    static func lastPosition(for url: URL) -> Position? {
        let table = defaults.dictionary(forKey: Key.lastPositions) ?? [:]
        guard let raw = table[url.path] as? [Double], raw.count >= 3 else { return nil }
        return Position(pageIndex: Int(raw[0]), x: raw[1], y: raw[2])
    }

    private static let maxPositions = 500

    static func setLastPosition(_ position: Position, for url: URL) {
        var table = defaults.dictionary(forKey: Key.lastPositions) ?? [:]
        table[url.path] = [Double(position.pageIndex), Double(position.x), Double(position.y),
                           Date().timeIntervalSinceReferenceDate]
        // Keep the table bounded by evicting the least recently used entries.
        if table.count > maxPositions {
            let byAge = table.keys.sorted { lhs, rhs in
                accessStamp(table[lhs]) < accessStamp(table[rhs])
            }
            for key in byAge.prefix(table.count - maxPositions) {
                table.removeValue(forKey: key)
            }
        }
        defaults.set(table, forKey: Key.lastPositions)
    }

    private static func accessStamp(_ raw: Any?) -> Double {
        guard let values = raw as? [Double], values.count >= 4 else { return 0 }
        return values[3]
    }
}
