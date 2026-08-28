import Foundation

/// The small slice of app state the desktop widget actually needs -- written
/// by the main app into the shared App Group container every time
/// IntentStore saves (or the panel theme changes), and read back by the
/// widget extension's TimelineProvider. Just the pending to-do texts, in the
/// same order as the main panel's own pending list -- no streaks/activity,
/// no completed items, no colors/reminders/IDs, per request -- plus the
/// current PanelTheme so the widget always matches the main panel's look.
/// Pure/dependency-free like ActivityStats and IntentEntry, so it's safe to
/// add to both targets' membership.
struct WidgetSnapshot: Codable {
    let pendingItems: [String]
    let theme: PanelTheme
    let generatedAt: Date

    /// The same group ID must be added as an App Group capability on both
    /// the main app target and the widget extension target in Xcode's
    /// Signing & Capabilities tab -- that's what actually provisions it,
    /// not this string alone.
    static let appGroupIdentifier = "group.com.plainspace.squirreltrap"

    private static let fileName = "widget_snapshot.json"

    /// nil until the App Group capability is actually configured on this
    /// target -- callers should treat a nil container as "widget isn't set
    /// up yet" and silently skip writing, not as an error.
    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let containerURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: containerURL.appendingPathComponent(fileName), options: .atomic)
    }

    static func read() -> WidgetSnapshot? {
        guard let containerURL, let data = try? Data(contentsOf: containerURL.appendingPathComponent(fileName)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
