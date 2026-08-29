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
        SettingsForm {
            Section("Last 7 Days") {
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
                                .font(Theme.secondary)
                                .foregroundStyle(Color.panelTextSecondary)
                        }
                    }
                }
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                            .font(Theme.secondary)
                            .foregroundStyle(Color.panelTextSecondary)
                    }
                }
                .frame(height: 130)
                // The chart is the row, so it gets the row's full width rather
                // than sitting in the control column beside an empty label.
                .frame(maxWidth: .infinity)

                LabeledContent {
                    Text("\(maxInASingleDay)")
                        .foregroundStyle(Color.panelTextPrimary)
                } label: {
                    SettingLabel("Best day")
                }

                LabeledContent {
                    Text(averagePerDay.formatted(.number.precision(.fractionLength(1))))
                        .foregroundStyle(Color.panelTextPrimary)
                } label: {
                    SettingLabel("Average per day")
                }
            }

            Section("Tips") {
                LabeledContent {
                    Toggle("", isOn: $preferences.showTips)
                        .labelsHidden()
                } label: {
                    SettingLabel("Show tips", "Occasional popovers that point out features like Snooze or Default Alarm. Turning this off doesn't lose your progress through them -- turn it back on and the rotation picks up where it left off.")
                }

                LabeledContent {
                    HStack(spacing: 6) {
                        Button("Reset") {
                            preferences.dismissedCoachTips = []
                            preferences.coachTipRotationIndex = 0
                            showResetConfirmation = true
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                showResetConfirmation = false
                            }
                        }
                        if showResetConfirmation {
                            Label("Reset", systemImage: "checkmark.circle")
                                .foregroundStyle(Color.panelTextSecondary)
                        }
                    }
                } label: {
                    SettingLabel("Dismissed tips", "Brings back every coach tip you've dismissed, so the rotation starts over.")
                }
            }
        }
    }
}
