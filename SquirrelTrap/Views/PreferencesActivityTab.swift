import Charts
import SwiftUI

struct PreferencesActivityTab: View {
    let intentStore: IntentStore
    @ObservedObject var preferences: AppPreferences

    @State private var showResetConfirmation = false

    private var days: [(date: Date, count: Int)] { intentStore.last7DaysCompletionCounts }

    private var maxInASingleDay: Int {
        days.map(\.count).max() ?? 0
    }

    private var averagePerDay: Double {
        guard !days.isEmpty else { return 0 }
        return Double(days.reduce(0) { $0 + $1.count }) / Double(days.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Completed per day, last 7 days")
                .font(.system(size: 12))
                .foregroundStyle(Color.panelTextSecondary)

            // The x-axis uses the actual Date (not a pre-formatted day-name
            // string) so Swift Charts orders bars chronologically -- a
            // categorical String axis sorts alphabetically instead (e.g. Fri
            // before Mon), which scrambled real data out of date order.
            Chart(days, id: \.date) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Completed", day.count)
                )
                .foregroundStyle(preferences.panelTheme.accent)
                .annotation(position: .top) {
                    if day.count > 0 {
                        Text("\(day.count)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.panelTextSecondary)
                    }
                }
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.panelTextSecondary)
                }
            }
            .frame(height: 160)

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Most Tasks In a Single Day")
                        .foregroundStyle(Color.panelTextSecondary)
                    Text("\(maxInASingleDay)")
                        .foregroundStyle(Color.panelTextPrimary)
                }
                GridRow {
                    Text("Average Tasks / Day")
                        .foregroundStyle(Color.panelTextSecondary)
                    Text(averagePerDay.formatted(.number.precision(.fractionLength(1))))
                        .foregroundStyle(Color.panelTextPrimary)
                }
            }
            .font(.system(size: 12))

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    HStack(spacing: 4) {
                        Text("Show Tips")
                            .foregroundStyle(Color.panelTextSecondary)
                            .lineLimit(1)
                        HelpTip("Occasional popovers that point out features like Snooze or Default Alarm. Turning this off doesn't lose your progress through them -- turn it back on and the rotation picks up where it left off.")
                    }
                    Toggle("", isOn: $preferences.showTips)
                        .labelsHidden()
                }
            }
            .font(.system(size: 12))

            HStack(spacing: 8) {
                Button("Reset All Tips") {
                    preferences.dismissedCoachTips = []
                    preferences.coachTipRotationIndex = 0
                    showResetConfirmation = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        showResetConfirmation = false
                    }
                }
                .help("Brings back every coach tip you've dismissed, so the rotation starts over")
                if showResetConfirmation {
                    Label("Reset", systemImage: "checkmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.panelTextSecondary)
                }
            }
            .font(.system(size: 12))
        }
    }
}
