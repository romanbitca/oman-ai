import Foundation
import OmanCore

/// Which template the panel opens on in an app, and where that choice is kept. A quick fix proofreads with the same
/// one, so a template's habits with capital letters and punctuation hold there too.
enum TemplateMemory {
    /// What an app's choice is kept under: its bundle identifier, its name where it has none, and one key for no
    /// app at all, so that a choice is remembered wherever it is made.
    static func key(for app: SourceApp?) -> String {
        guard let app else { return "none" }
        return app.bundleID ?? "name:\(app.name)"
    }

    /// The chip chosen last in this app, As written included, as nil. An app nothing was chosen in yet, or one whose
    /// template has since been deleted, starts on the default from Settings.
    static func preselectedStyleID(
        for app: SourceApp?,
        styles: [WritingStyle],
        preferences: AppPreferences,
        store: any StyleStore
    ) -> UUID? {
        if preferences.remembersStylePerApp, let choice = try? store.lastStyleChoice(forApp: key(for: app)) {
            switch choice {
            case .asWritten:
                return nil
            case .style(let id):
                if styles.contains(where: { $0.id == id }) { return id }
            }
        }
        return styles.first(where: { $0.id == preferences.defaultStyleID })?.id
    }
}
