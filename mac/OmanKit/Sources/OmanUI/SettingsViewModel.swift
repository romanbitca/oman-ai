import Foundation
import Observation
import OmanCore

@MainActor
@Observable
public final class SettingsViewModel {
    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private(set) var tryTask: Task<Void, Never>?

    private(set) var hasAPIKey = false
    private(set) var isValidatingKey = false
    private(set) var apiKeyError: String?
    var apiKeyDraft = ""

    private(set) var selectedModel: ClaudeModel = .default
    private(set) var modelError: String?

    private(set) var isAccessibilityGranted = false
    private(set) var isScreenCaptureGranted = false
    private(set) var isLaunchAtLogin = false
    private(set) var launchAtLoginError: String?

    private(set) var styles: [WritingStyle] = []
    private(set) var selectedStyleID: UUID?
    private(set) var styleError: String?
    var newSampleText = ""

    var tryItText = ""
    private(set) var tryItResult = ""
    private(set) var tryItError: String?
    private(set) var isTrying = false

    public init(services: AppServices) {
        self.services = services
    }

    public func reload() {
        hasAPIKey = loadAPIKey() != nil
        apiKeyDraft = ""
        apiKeyError = nil
        selectedModel = (try? services.settings.selectedModel()) ?? .default
        refreshPermissions()
        do {
            styles = try services.styles.loadStyles()
            styleError = nil
        } catch {
            styles = []
            styleError = error.localizedDescription
        }
        if !styles.contains(where: { $0.id == selectedStyleID }) {
            selectedStyleID = styles.first?.id
        }
    }

    private func loadAPIKey() -> String? {
        guard let key = try? services.apiKeys.loadAPIKey(), !key.isEmpty else { return nil }
        return key
    }

    // MARK: General

    func refreshPermissions() {
        isAccessibilityGranted = services.system.isAccessibilityGranted
        isScreenCaptureGranted = services.system.isScreenCaptureGranted
        isLaunchAtLogin = services.system.isLaunchAtLoginEnabled
    }

    func saveAPIKey() async {
        let key = apiKeyDraft.trimmed
        guard !key.isEmpty, !isValidatingKey else { return }
        isValidatingKey = true
        apiKeyError = nil
        defer { isValidatingKey = false }
        do {
            try await services.writing.validate(apiKey: key)
            try services.apiKeys.saveAPIKey(key)
            apiKeyDraft = ""
            hasAPIKey = true
        } catch {
            apiKeyError = error.localizedDescription
        }
    }

    func removeAPIKey() {
        do {
            try services.apiKeys.deleteAPIKey()
            hasAPIKey = false
            apiKeyError = nil
        } catch {
            apiKeyError = error.localizedDescription
        }
    }

    func setModel(_ model: ClaudeModel) {
        do {
            try services.settings.setSelectedModel(model)
            selectedModel = model
            modelError = nil
        } catch {
            modelError = error.localizedDescription
        }
    }

    func requestAccessibility() {
        services.system.requestAccessibility()
    }

    func requestScreenCapture() {
        services.system.requestScreenCapture()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try services.system.setLaunchAtLogin(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        isLaunchAtLogin = services.system.isLaunchAtLoginEnabled
    }

    // MARK: Styles

    var selectedStyle: WritingStyle? { styles.first { $0.id == selectedStyleID } }

    var sampleSummary: String {
        let samples = selectedStyle?.samples ?? []
        let words = samples.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
        return "\(samples.count) \(samples.count == 1 ? "sample" : "samples"), \(words) \(words == 1 ? "word" : "words")"
    }

    func selectStyle(_ id: UUID?) {
        guard id != selectedStyleID else { return }
        tryTask?.cancel()
        tryTask = nil
        selectedStyleID = id
        newSampleText = ""
        tryItText = ""
        tryItResult = ""
        tryItError = nil
        isTrying = false
    }

    func createStyle() {
        let style = WritingStyle(name: "New style")
        styles.append(style)
        persist(style)
        selectStyle(style.id)
    }

    func deleteSelectedStyle() {
        guard let id = selectedStyleID else { return }
        do {
            try services.styles.deleteStyle(id: id)
            styles.removeAll { $0.id == id }
            selectStyle(styles.first?.id)
            styleError = nil
        } catch {
            styleError = error.localizedDescription
        }
    }

    func updateName(_ name: String) {
        updateSelectedStyle { $0.name = name }
    }

    func updateNote(_ note: String) {
        updateSelectedStyle { $0.note = note }
    }

    func addSample() {
        let text = newSampleText.trimmed
        guard !text.isEmpty else { return }
        updateSelectedStyle { $0.samples.append(StyleSample(text: text)) }
        newSampleText = ""
    }

    func removeSample(id: UUID) {
        updateSelectedStyle { $0.samples.removeAll { $0.id == id } }
    }

    private func updateSelectedStyle(_ change: (inout WritingStyle) -> Void) {
        guard let index = styles.firstIndex(where: { $0.id == selectedStyleID }) else { return }
        change(&styles[index])
        persist(styles[index])
    }

    private func persist(_ style: WritingStyle) {
        do {
            try services.styles.save(style)
            styleError = nil
        } catch {
            styleError = error.localizedDescription
        }
    }

    // MARK: Try it

    func tryIt() {
        let text = tryItText.trimmed
        guard !text.isEmpty, let style = selectedStyle else { return }
        tryTask?.cancel()
        tryItResult = ""
        tryItError = nil
        guard let apiKey = loadAPIKey() else {
            isTrying = false
            tryItError = WritingError.missingAPIKey.localizedDescription
            return
        }
        let request = WritingRequest(
            task: .rewrite(text: text, instruction: nil),
            style: style,
            model: (try? services.settings.selectedModel()) ?? .default
        )
        let stream = services.writing.stream(request, apiKey: apiKey)
        isTrying = true
        tryTask = Task { [weak self] in
            do {
                for try await delta in stream {
                    guard let self, !Task.isCancelled else { return }
                    self.tryItResult += delta
                }
                guard let self, !Task.isCancelled else { return }
                self.isTrying = false
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.tryItResult = ""
                self.tryItError = error.localizedDescription
                self.isTrying = false
            }
        }
    }
}
