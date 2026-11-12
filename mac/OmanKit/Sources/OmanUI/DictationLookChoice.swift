import OmanCore
import SwiftUI

/// The two looks of the dictation pill side by side, each drawn small over a desktop, to choose from.
struct LookChoice: View {
    let model: SettingsViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(DictationPillStyle.allCases) { style in
                let isChosen = model.preferences.dictationPillStyle == style
                Button {
                    model.updatePreferences { $0.dictationPillStyle = style }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        LookPicture(style: style)
                            .frame(height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        isChosen ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                                        lineWidth: isChosen ? 2.5 : 1
                                    )
                            }
                        HStack(spacing: 6) {
                            Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isChosen ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                            Text(style.displayName).fontWeight(.medium)
                        }
                        Text(style.explanation)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(style.displayName)
                .accessibilityAddTraits(isChosen ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}

extension DictationPillStyle {
    var explanation: String {
        switch self {
        case .card: "The seconds and buttons above, and your words below in a glass card."
        case .floating: "Your words on a soft blur with no box, above the seconds and buttons."
        }
    }
}

/// A small drawing of a look over a desktop. Not the real glass, which can only be drawn on the screen.
private struct LookPicture: View {
    let style: DictationPillStyle

    private let words = "Hi Ana, thanks for the notes from Friday. I'll send the plan tonight"

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.36, green: 0.42, blue: 0.62), Color(red: 0.86, green: 0.55, blue: 0.42)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(spacing: 6) {
                switch style {
                case .card: card
                case .floating: floating
                }
            }
            .padding(.horizontal, 16)
            .environment(\.colorScheme, .dark)
        }
        .accessibilityHidden(true)
    }

    private var card: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                circle { wave }
                capsule { Text("0:08").font(.system(size: 9, weight: .medium).monospacedDigit()) }
                Spacer(minLength: 0)
                circle { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                circle { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)) }
            }
            Text(words)
                .font(.system(size: 9.5))
                .foregroundStyle(.white)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(glass(RoundedRectangle(cornerRadius: 10, style: .continuous)))
        }
    }

    private var floating: some View {
        VStack(spacing: 6) {
            Text(words)
                .font(.system(size: 9.5))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .shadow(color: .black.opacity(0.5), radius: 3)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    EllipticalGradient(colors: [.black.opacity(0.45), .black.opacity(0.3), .clear], center: .center)
                        .blur(radius: 6)
                }
            HStack(spacing: 5) {
                capsule {
                    HStack(spacing: 4) {
                        wave
                        Text("0:08").font(.system(size: 9, weight: .medium).monospacedDigit())
                    }
                }
                circle { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                circle { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)) }
            }
        }
    }

    private var wave: some View {
        DictationWave(amplitude: 0.8)
            .stroke(.white, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            .frame(width: 11, height: 11)
    }

    private func circle(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(glass(Circle()))
    }

    private func capsule(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(glass(Capsule()))
    }

    private func glass(_ shape: some Shape) -> some View {
        shape
            .fill(.white.opacity(0.16))
            .overlay { shape.stroke(.white.opacity(0.35), lineWidth: 0.6) }
    }
}
