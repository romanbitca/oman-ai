import AppKit

struct PasteboardSnapshot {
    private struct Representation {
        let type: NSPasteboard.PasteboardType
        let data: Data
    }

    private let items: [[Representation]]

    init(of pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { Representation(type: type, data: $0) }
            }
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { representations in
            let item = NSPasteboardItem()
            for representation in representations {
                item.setData(representation.data, forType: representation.type)
            }
            return item
        }
        if !restored.isEmpty {
            pasteboard.writeObjects(restored)
        }
    }

    /// Leaves the pasteboard alone if anything was copied since `changeCount` was read.
    func restore(to pasteboard: NSPasteboard, ifChangeCountIs changeCount: Int) {
        guard pasteboard.changeCount == changeCount else { return }
        restore(to: pasteboard)
    }
}

/// Hands pasted text over only when an app asks for it. That request is the one sign that a paste was read.
final class PasteReceipt: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    private let text: String
    private let lock = NSLock()
    private var read = false

    init(text: String) {
        self.text = text
    }

    var wasRead: Bool { lock.withLock { read } }

    func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {
        item.setString(text, forType: type)
        lock.withLock { read = true }
    }
}

extension NSPasteboard {
    static let transientType = PasteboardType("org.nspasteboard.TransientType")
    static let concealedType = PasteboardType("org.nspasteboard.ConcealedType")

    /// Looks at the types only. Text that a password manager marked as concealed, or that is only passing
    /// through, is not offered.
    var offersPlainText: Bool {
        guard let types, types.contains(.string) else { return false }
        return !types.contains(Self.concealedType) && !types.contains(Self.transientType)
    }

    /// Marked transient so clipboard history apps skip text that is only passing through.
    /// The returned receipt says whether any app has asked for the text yet.
    @discardableResult
    func writeTransientString(_ text: String) -> PasteReceipt {
        clearContents()
        let receipt = PasteReceipt(text: text)
        let item = NSPasteboardItem()
        item.setDataProvider(receipt, forTypes: [.string])
        item.setData(Data(), forType: Self.transientType)
        writeObjects([item])
        return receipt
    }
}
