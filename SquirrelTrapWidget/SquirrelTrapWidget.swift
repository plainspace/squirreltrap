//
//  SquirrelTrapWidget.swift
//  SquirrelTrapWidget
//

import WidgetKit
import SwiftUI

/// Purely push-driven -- .never means WidgetKit won't waste its own refresh
/// budget on a schedule that would just show stale data between real
/// updates anyway. The main app calls WidgetCenter.reloadAllTimelines()
/// itself whenever entries change (see AppDelegate.publishWidgetSnapshot in
/// the main target), which is what actually drives new timelines.
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: WidgetSnapshot(pendingItems: ["Reply to Sam", "Pick up dry cleaning", "Draft Q3 outline"], generatedAt: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: WidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(Timeline(entries: [SnapshotEntry(date: Date(), snapshot: WidgetSnapshot.read())], policy: .never))
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    /// nil until the main app has run at least once since the widget was
    /// added (no snapshot has ever been written yet).
    let snapshot: WidgetSnapshot?
}

/// The same two-layer color recipe PanelController uses for the real panel:
/// a fixed opaque dark blue base (its opaqueFallbackView color) plus the
/// accent-blue tint overlay on top -- so the widget reads as "Squirrel Trap
/// blue" consistently regardless of desktop wallpaper, the same way the
/// panel does regardless of what's behind it.
private let widgetBackground = LinearGradient(
    colors: [
        Color(red: 0x2A / 255, green: 0x3D / 255, blue: 0x63 / 255),
        Color(red: 0x24 / 255, green: 0x89 / 255, blue: 0xFF / 255).opacity(0.22),
    ],
    startPoint: .top,
    endPoint: .bottom
)

struct SquirrelTrapWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: Provider.Entry

    private var maxItems: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 5
        default: return 10
        }
    }

    private var showsHeader: Bool { family != .systemSmall }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsHeader {
                Text("Squirrel Trap")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.panelTextSecondary)
            }

            if let snapshot = entry.snapshot {
                if snapshot.pendingItems.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.title2)
                        Text("All caught up")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.panelTextSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let shown = Array(snapshot.pendingItems.prefix(maxItems))
                    let remaining = snapshot.pendingItems.count - shown.count
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(shown.enumerated()), id: \.offset) { _, text in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "circle")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.accentColor.opacity(0.7))
                                    .padding(.top, 2)
                                Text(text)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.panelTextPrimary)
                                    .lineLimit(1)
                            }
                        }
                        if remaining > 0 {
                            Text("+\(remaining) more")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.panelTextSecondary)
                        }
                    }
                }
            } else {
                Text("Open Squirrel Trap to get started")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.panelTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SquirrelTrapWidget: Widget {
    let kind: String = "SquirrelTrapWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(macOS 14.0, *) {
                SquirrelTrapWidgetEntryView(entry: entry)
                    .containerBackground(for: .widget) { widgetBackground }
            } else {
                SquirrelTrapWidgetEntryView(entry: entry)
                    .padding()
                    .background(widgetBackground)
            }
        }
        .configurationDisplayName("Squirrel Trap")
        .description("Your pending to-dos, at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
