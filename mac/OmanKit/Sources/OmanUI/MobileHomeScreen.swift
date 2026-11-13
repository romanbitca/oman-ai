#if os(iOS)
import OmanCore
import SwiftUI

/// OmanAI's own window on the iPhone: the same tiles, the year and the transcripts, one under the other.
struct MobileHomeScreen: View {
    @Bindable var model: HomeViewModel
    @State private var metric = HomeSummary.MapMetric.words
    var calendar = Calendar.current

    private var summary: HomeSummary { model.summary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HomeMetrics.gap) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(summary.period.title)
                        .font(.system(size: 30, weight: .bold))
                        .tracking(-0.4)
                        .contentTransition(.opacity)
                    HomeChips(values: HomeSummary.Period.allCases, selection: $model.period) { $0.title }
                }
                .padding(.bottom, 4)

                HomeHeroTile(
                    summary: summary, calendar: calendar,
                    dictationKeys: model.dictationKeys, proofreadKeys: model.proofreadKeys, pointingAt: nil
                )

                let small = summary.smallTiles
                HomeColumns(spans: Array(repeating: 6 / max(small.count, 1), count: small.count)) {
                    ForEach(Array(small.enumerated()), id: \.offset) { _, tile in
                        switch tile {
                        case .streak: HomeStreakTile(streak: summary.streak, calendar: calendar)
                        case .speed: HomeSpeedTile(summary: summary, period: summary.period)
                        case .dictateTip: HomeDictateTipTile(keys: model.dictationKeys)
                        }
                    }
                }

                // Two to a row, as wide tiles are on the Mac three to a row.
                let wide = summary.wideTiles
                ForEach(Array(stride(from: 0, to: wide.count, by: 2)), id: \.self) { start in
                    let row = Array(wide[start..<min(start + 2, wide.count)])
                    HomeColumns(spans: Array(repeating: 6 / row.count, count: row.count)) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, tile in
                            wideTile(tile, isAlone: wide.count == 1)
                        }
                    }
                }

                HomeMapCard(summary: summary, metric: $metric, calendar: calendar, pointingAt: nil)

                HomeTranscripts(model: model, pointingAt: nil)
                    .padding(.top, 14)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(HomePalette.ink)
        .background(HomePalette.page)
        .onAppear { model.reload() }
        .onReceive(NotificationCenter.default.publisher(for: Platform.didBecomeActive)) { _ in
            model.reload()
        }
    }

    @ViewBuilder
    private func wideTile(_ tile: HomeSummary.WideTile, isAlone: Bool) -> some View {
        switch tile {
        case .timeSaved: HomeTimeSavedTile(summary: summary, isAccent: summary.accentTile == .timeSaved)
        case .fixes: HomeFixesTile(fixes: summary.fixes, period: summary.period)
        case .english: HomeEnglishTile(summary: summary, isAccent: summary.accentTile == .english)
        case .apps: HomeAppsTile(summary: summary) { model.appURL(named: $0) }
        case .englishInvite: HomeEnglishInviteTile(keys: model.proofreadKeys, isAlone: isAlone)
        }
    }
}
#endif
