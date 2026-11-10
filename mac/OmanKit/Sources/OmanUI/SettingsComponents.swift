import SwiftUI

enum SettingsMetrics {
    static let gap: CGFloat = 8
    static let outer: CGFloat = 6
    static let inset = RoundedRectangle(cornerRadius: 13, style: .continuous)
}

struct SettingsTile<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { WindowDragArea() }
        .liquidGlass(in: PanelShape.tile)
    }
}

struct SettingsRow<Accessory: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            accessory
        }
    }
}

struct SettingsToggleRow: View {
    let title: String
    var detail: String?
    let isOn: Binding<Bool>

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Liquid.accent)
        }
    }
}

struct LiquidSegmented<Option: Hashable>: View {
    let options: [Option]
    let selection: Option
    let title: (Option) -> String
    let onSelect: (Option) -> Void
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(Liquid.press) { onSelect(option) }
                } label: {
                    Text(title(option))
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 15)
                        .frame(height: 30)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Liquid.accent)
                                    .matchedGeometryEffect(id: "selected", in: highlight)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(LiquidPressStyle())
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.07), in: Capsule())
    }
}

struct SettingsTextField: View {
    let prompt: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(prompt, text: $text)
            .textFieldStyle(.plain)
            .focusEffectDisabled()
            .font(.system(size: 13))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Color.primary.opacity(0.07), in: Capsule())
            .onSubmit(onSubmit)
    }
}

struct SettingsTextBox: View {
    let prompt: String
    @Binding var text: String
    var height: CGFloat = 96

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .focusEffectDisabled()
            .frame(height: height)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(prompt)
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.07), in: SettingsMetrics.inset)
    }
}
