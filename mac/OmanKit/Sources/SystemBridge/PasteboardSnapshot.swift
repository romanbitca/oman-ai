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

extension NSPasteboard {
    static let transientType = PasteboardType("org.nspasteboard.TransientType")

    /// Marked transient so clipboard history apps skip text that is only passing through.
    func writeTransientString(_ text: String) {
        clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: Self.transientType)
        writeObjects([item])
    }
}
