#if os(iOS)
import OmanCore
import SwiftUI
import UIKit

/// Dictation on the iPhone: a microphone to tap, the words as they are said, and then Copy, Proofread or Rewrite.
/// Finished words are also copied, so they can be pasted in any app straight away.
struct MobileDictationScreen: View {
    let controller: DictationController
    let router: MobileRouter
    @State private var copiedAgain = false

    var body: some View {
        ZStack {
            MobileBackground()
            VStack(alignment: .leading, spacing: PanelMetrics.gap) {
                header
                wordsCard
                if showsActions { actions }
                if let notice = controller.notice, !controller.isActive {
                    NoticeText(text: notice).padding(.horizontal, 6)
                }
                Spacer(minLength: 0)
                microphone
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 20)
            .frame(maxWidth: 560)
        }
        .animation(.easeOut(duration: 0.2), value: controller.phase)
        .animation(.easeOut(duration: 0.2), value: controller.lastText)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Dictate").font(.system(size: 30, weight: .bold)).tracking(-0.4)
            Text(controller.modelName + " · on this iPhone")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private var wordsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if controller.isActive {
                if controller.isLoadingModel, controller.transcript.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Getting \(controller.modelName) ready. It is already listening.")
                            .foregroundStyle(.secondary)
                    }
                } else if controller.transcript.isEmpty {
                    Text(controller.phase == .finishing ? "Finishing…" : "Listening…").foregroundStyle(.secondary)
                } else {
                    LiveWords(transcript: controller.transcript, alignment: .leading)
                }
            } else if let text = controller.lastText {
                Text(text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Label(copiedAgain ? "Copied again" : "Copied. Paste it in any app.", systemImage: "checkmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Text("Tap the microphone and talk. Your words show here as you say them, and are copied when you finish.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 17))
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .liquidGlass(in: PanelShape.tile, id: "dictation-words", reading: true)
    }

    private var showsActions: Bool { !controller.isActive && controller.lastText != nil }

    private var actions: some View {
        HStack(spacing: 8) {
            LiquidButton(title: "Copy", symbol: "doc.on.doc") {
                guard let text = controller.lastText else { return }
                UIPasteboard.general.string = text
                copiedAgain = true
            }
            LiquidButton(title: "Proofread", symbol: "text.magnifyingglass") {
                guard let text = controller.lastText else { return }
                router.open(text) { $0.proofread() }
            }
            LiquidButton(title: "Rewrite", symbol: "arrow.trianglehead.2.clockwise") {
                guard let text = controller.lastText else { return }
                router.open(text) { $0.rewrite() }
            }
        }
        .onChange(of: controller.lastText) { _, _ in copiedAgain = false }
    }

    private var microphone: some View {
        VStack(spacing: 10) {
            ZStack {
                Button {
                    if controller.isActive { controller.finishNow() } else { controller.longPressed(into: nil) }
                } label: {
                    ZStack {
                        if controller.phase == .listening {
                            DictationWave(amplitude: DictationWave.amplitude(forLevel: controller.level))
                                .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                                .frame(width: 46, height: 46)
                                .animation(.easeOut(duration: 0.1), value: controller.level)
                        } else if controller.phase == .finishing || controller.phase == .starting {
                            ProgressView()
                        } else {
                            Image(systemName: "mic.fill").font(.system(size: 34, weight: .semibold))
                        }
                    }
                    .foregroundStyle(controller.isActive ? .white : MobilePalette.accent)
                    .frame(width: 104, height: 104)
                    .background {
                        if controller.isActive { Circle().fill(MobilePalette.accent) }
                    }
                    .contentShape(Circle())
                    .liquidGlass(in: Circle(), id: "dictation-mic", interactive: true)
                }
                .buttonStyle(GlassPressStyle())
                .accessibilityLabel(controller.isActive ? "Finish dictating" : "Dictate")

                if controller.isActive {
                    Button {
                        controller.cancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 46, height: 46)
                            .contentShape(Circle())
                            .liquidGlass(in: Circle(), id: "dictation-cancel", interactive: true)
                    }
                    .buttonStyle(GlassPressStyle())
                    .accessibilityLabel("Cancel")
                    .offset(x: -100)
                    .transition(.opacity)
                }
            }
            elapsed
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var elapsed: some View {
        if let since = controller.listeningSince {
            TimelineView(.periodic(from: since, by: 1)) { context in
                Text(Duration.seconds(max(0, context.date.timeIntervalSince(since))).formatted(.time(pattern: .minuteSecond)))
                    .font(.system(size: 15, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(controller.isActive ? " " : "Tap to start, and tap again when you are done")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}
#endif
