import AppKit
import OmanCore
import SwiftUI

/// OmanAI's own window: what it did for the person in a stretch of time, the year at a glance, and their
/// transcripts.
struct HomeView: View {
    @Bindable var model: HomeViewModel
    @State private var metric = HomeSummary.MapMetric.words
    var calendar = Calendar.current
    /// For drawing the window as it looks with the pointer on today's square and on a transcript.
    var showsPointer = false

    private var summary: HomeSummary { model.summary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text(summary.period.title)
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-0.4)
                        .contentTransition(.opacity)
                    Spacer(minLength: 8)
                    HomeChips(values: HomeSummary.Period.allCases, selection: $model.period) { $0.title }
                }
                .padding(.bottom, 14)

                HomeColumns(spans: [4, 2]) {
                    HomeHeroTile(
                        summary: summary, calendar: calendar,
                        dictationKeys: model.dictationKeys, proofreadKeys: model.proofreadKeys
                    )
                    VStack(spacing: HomeMetrics.gap) {
                        ForEach(Array(summary.smallTiles.enumerated()), id: \.offset) { _, tile in
                            switch tile {
                            case .streak: HomeStreakTile(streak: summary.streak, calendar: calendar)
                            case .speed: HomeSpeedTile(summary: summary, period: summary.period)
                            case .dictateTip: HomeDictateTipTile(keys: model.dictationKeys)
                            }
                        }
                    }
                }

                let wide = summary.wideTiles
                HomeColumns(spans: Array(repeating: 6 / max(wide.count, 1), count: wide.count)) {
                    ForEach(Array(wide.enumerated()), id: \.offset) { _, tile in
                        switch tile {
                        case .timeSaved: HomeTimeSavedTile(summary: summary, isAccent: summary.accentTile == .timeSaved)
                        case .fixes: HomeFixesTile(fixes: summary.fixes, period: summary.period)
                        case .english: HomeEnglishTile(summary: summary, isAccent: summary.accentTile == .english)
                        case .apps: HomeAppsTile(summary: summary) { model.appURL(named: $0) }
                        case .englishInvite: HomeEnglishInviteTile(keys: model.proofreadKeys, isAlone: wide.count == 1)
                        }
                    }
                }
                .padding(.top, HomeMetrics.gap)

                HomeMapCard(
                    summary: summary, metric: $metric, calendar: calendar,
                    pointingAt: showsPointer ? summary.map.indices.last.map { .init(week: $0, day: max(summary.map[$0].count - 1, 0)) } : nil
                )
                .padding(.top, HomeMetrics.gap)

                HomeTranscripts(model: model, pointingAt: showsPointer ? model.transcripts.dropFirst().first?.id : nil)
                    .padding(.top, 22)
            }
            .padding(.horizontal, HomeMetrics.sideMargin)
            .padding(.top, 6)
            .padding(.bottom, 24)
            .frame(maxWidth: HomeMetrics.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(HomePalette.ink)
        .background(HomePalette.page)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.reload()
        }
        .withoutSystemWritingTools()
    }
}
