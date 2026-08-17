//
//  SquirrelTrapWidget.swift
//  SquirrelTrapWidget
//

import WidgetKit
import SwiftUI

/// Purely push-driven -- .never means WidgetKit won't waste its own refresh
/// budget on a schedule that would just show stale data between real
/// updates anyway. The main app calls WidgetCenter.reloadAllTimelines()
/// itself whenever entries change or showStreak is toggled (see
/// AppDelegate.publishWidgetSnapshot in the main target), which is what
/// actually drives new timelines.
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: WidgetSnapshot(currentStreak: 3, showStreak: true, todayCompletedCount: 2, generatedAt: Date()))
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
    var entry: Provider.Entry

    var body: some View {
        if let snapshot = entry.snapshot {
            VStack(spacing: 6) {
                if snapshot.showStreak {
                    HStack(spacing: 4) {
                        Text("🔥")
                        Text("\(snapshot.currentStreak)")
                            .fontWeight(.bold)
                        Text(snapshot.currentStreak == 1 ? "day" : "days")
                            .foregroundStyle(.secondary)
                    }
                    .font(.title3)
                }
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                    Text("\(snapshot.todayCompletedCount) today")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
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
        .description("Your current streak and today's completed count.")
        .supportedFamilies([.systemSmall])
    }
}
