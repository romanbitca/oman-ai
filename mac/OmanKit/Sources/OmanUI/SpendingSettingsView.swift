import Charts
import SwiftUI

struct SpendingSettingsView: View {
    let model: SettingsViewModel
    @State private var period = SpendingSummary.Period.thisMonth

    private var summary: SpendingSummary.PeriodSummary { model.spending[period] }

    private var detail: String {
        guard summary.requests > 0 else { return "No requests" }
        return [
            SpendingFormat.requests(summary.requests),
            SpendingFormat.tokens(summary.tokens),
            "\(SpendingFormat.average(summary.averageCost)) each",
        ].joined(separator: " · ")
    }

    private var note: String {
        let estimate = "Estimated from the tokens Anthropic reports for each request, at list prices. "
            + "Only OmanAI on this Mac is counted, and Apple's on-device model is free."
        return model.spending.hasEntries
            ? estimate
            : "Nothing yet. OmanAI counts each Claude request from this version on. " + estimate
    }

    var body: some View {
        SettingsForm {
            Section {
                Picker("Period", selection: $period) {
                    ForEach(SpendingSummary.Period.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                VStack(alignment: .leading, spacing: 3) {
                    Text(SpendingFormat.amount(summary.cost))
                        .font(.system(size: 28, weight: .semibold))
                        .monospacedDigit()
                    Text(detail).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)

                SpendingChart(bars: summary.bars, period: period)

                if let error = model.spendingError {
                    SettingsError(text: error)
                }
            } footer: {
                Text(note)
            }

            if !summary.models.isEmpty {
                Section("By model") {
                    ForEach(summary.models) { share in
                        LabeledContent(share.name) {
                            HStack(spacing: 14) {
                                Text(SpendingFormat.requests(share.requests)).foregroundStyle(.tertiary)
                                Text(SpendingFormat.amount(share.cost))
                                    .monospacedDigit()
                                    .frame(minWidth: 64, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { model.reloadSpending() }
    }
}

struct SpendingChart: View {
    let bars: [SpendingSummary.Bar]
    let period: SpendingSummary.Period

    private var labelFormat: Date.FormatStyle {
        switch period {
        case .today: .dateTime.hour()
        case .thisWeek: .dateTime.weekday(.abbreviated)
        case .thisMonth, .lastMonth: .dateTime.day().month(.abbreviated)
        case .allTime: bars.count > 12 ? .dateTime.month(.abbreviated).year(.twoDigits) : .dateTime.month(.abbreviated)
        }
    }

    var body: some View {
        Chart(bars) { bar in
            BarMark(
                x: .value("Date", bar.start, unit: period.barUnit),
                y: .value("Spent", bar.cost)
            )
            .foregroundStyle(Color.accentColor)
            .cornerRadius(3)
        }
        // An hour, day or month with nothing spent still needs an axis to sit on.
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
            // Each label is centred under its own bar. Charts would otherwise start it at the bar, which runs the
            // last one off the chart, or centre it between marks, days away from its bar. The aligned preset also
            // moves a label at either end inwards far enough to stay on the chart.
            AxisMarks(preset: .aligned, values: SpendingSummary.labelledBars(bars, for: period).map(\.middle)) { _ in
                AxisValueLabel(format: labelFormat)
            }
        }
        .frame(height: 140)
        .padding(.vertical, 4)
    }
}
