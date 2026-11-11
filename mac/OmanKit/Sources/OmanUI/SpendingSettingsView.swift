import Charts
import SwiftUI

struct SpendingSettingsView: View {
    let model: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.gap) {
            SettingsTile {
                HStack(alignment: .top, spacing: 36) {
                    total(title: "Today", dollars: model.spending.today)
                    total(title: "This week", dollars: model.spending.thisWeek)
                    Spacer(minLength: 0)
                }
                if !model.spending.hasEntries {
                    NoticeText(text: "Nothing yet. OmanAI counts each Claude request from this version on.")
                }
                if let error = model.spendingError {
                    NoticeText(text: error)
                }
            }

            SettingsTile(title: "Per day") {
                SpendingChart(bars: model.spending.days, unit: .day)
            }

            SettingsTile(title: "Per week") {
                SpendingChart(bars: model.spending.weeks, unit: .weekOfYear)
            }

            NoticeText(
                text: "Estimated from the tokens Anthropic reports for each request, at list prices. "
                    + "Only OmanAI on this Mac is counted, and Apple's on-device model is free."
            )
            .padding(.horizontal, 6)
        }
        .onAppear { model.reloadSpending() }
    }

    private func total(title: String, dollars: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(SpendingFormat.amount(dollars))
                .font(.system(size: 26, weight: .semibold))
                .monospacedDigit()
        }
    }
}

private struct SpendingChart: View {
    let bars: [SpendingSummary.Bar]
    let unit: Calendar.Component

    var body: some View {
        Chart(bars) { bar in
            BarMark(
                x: .value("Date", bar.start, unit: unit),
                y: .value("Spent", bar.cost)
            )
            .foregroundStyle(Liquid.accent)
            .cornerRadius(3)
        }
        // A day or week with nothing spent still needs an axis to sit on.
        .chartYScale(domain: 0...max(bars.map(\.cost).max() ?? 0, 0.01))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let dollars = value.as(Double.self) {
                        Text(SpendingFormat.axis(dollars))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: bars.map(\.start)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
            }
        }
        .frame(height: 150)
        // Settings has no animation at all.
        .transaction { $0.animation = nil }
    }
}
