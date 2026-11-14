import OmanCore
import SwiftUI

/// Settings' switch for syncing through iCloud, on the Mac and the iPhone. Shown only in builds that can sync.
struct CloudSyncSection: View {
    let sync: any CloudSyncing

    static let explanation = "Keeps your styles, actions and writing settings the same on each device signed in to "
        + "your Apple Account. Your API key, transcripts and dictation models stay on each device."

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { sync.isOn }, set: { sync.setOn($0) })) {
                Text("Sync with iCloud")
                #if os(macOS)
                Text(Self.explanation)
                #endif
            }
            if sync.isOn {
                LabeledContent {
                    Button("Sync Now") { sync.syncNow() }
                        .disabled(sync.status == .syncing)
                } label: {
                    Text(sync.status.sentence)
                }
            }
        } header: {
            Text("iCloud")
        } footer: {
            #if os(iOS)
            Text(Self.explanation)
            #endif
        }
    }
}

extension CloudSyncStatus {
    var sentence: String {
        switch self {
        case .off: "Off"
        case .syncing: "Syncing…"
        case .upToDate: "Up to date"
        #if os(macOS)
        case .noAccount: "Sign in to iCloud in System Settings to sync."
        #else
        case .noAccount: "Sign in to iCloud in Settings to sync."
        #endif
        case let .unavailable(reason): reason
        }
    }
}
