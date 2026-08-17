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

    var body: some View {
        if let snapshot = entry.snapshot {
            if snapshot.pendingItems.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("All caught up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                let shown = Array(snapshot.pendingItems.prefix(maxItems))
                let remaining = snapshot.pendingItems.count - shown.count
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, text in
                        HStack(alignment: .top, spacing: 5) {
                            Image(systemName: "circle")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                                .padding(.top, 3)
                            Text(text)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                    if remaining > 0 {
                        Text("+\(remaining) more")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Open Squirrel Trap to get started")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

struct SquirrelTrapWidget: Widget {
    let kind: String = "SquirrelTrapWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(macOS 14.0, *) {
                SquirrelTrapWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                SquirrelTrapWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("Squirrel Trap")
        .description("Your pending to-dos, at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
