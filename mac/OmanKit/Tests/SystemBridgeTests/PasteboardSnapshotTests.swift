import AppKit
import Testing
@testable import SystemBridge

@Suite struct PasteboardSnapshotTests {
    private let customType = NSPasteboard.PasteboardType("com.romanbitca.oman.test")

    private func withPasteboard(_ body: (NSPasteboard) throws -> Void) rethrows {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("oman-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        try body(pasteboard)
    }

    private func item(string: String, custom: Data? = nil) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(string, forType: .string)
        if let custom {
            item.setData(custom, forType: customType)
        }
        return item
    }

    @Test func restoresEveryItemAndType() throws {
        try withPasteboard { pasteboard in
            let custom = Data([0x01, 0x02, 0x03])
            pasteboard.clearContents()
            pasteboard.writeObjects([item(string: "first", custom: custom), item(string: "second")])

            let snapshot = PasteboardSnapshot(of: pasteboard)
            pasteboard.clearContents()
            pasteboard.setString("overwritten", forType: .string)
            snapshot.restore(to: pasteboard)

            let items = try #require(pasteboard.pasteboardItems)
            #expect(items.count == 2)
            #expect(items[0].string(forType: .string) == "first")
            #expect(items[0].data(forType: customType) == custom)
            #expect(items[1].string(forType: .string) == "second")
            #expect(items[1].data(forType: customType) == nil)
        }
    }

    @Test func snapshotIsIndependentOfLaterWrites() throws {
        try withPasteboard { pasteboard in
            let original = Data([0xAA, 0xBB])
            pasteboard.clearContents()
            pasteboard.writeObjects([item(string: "original", custom: original)])

            let snapshot = PasteboardSnapshot(of: pasteboard)
            pasteboard.clearContents()
            pasteboard.writeObjects([item(string: "changed", custom: Data([0xCC]))])
            #expect(pasteboard.pasteboardItems?.first?.data(forType: customType) == Data([0xCC]))

            snapshot.restore(to: pasteboard)
            let restored = try #require(pasteboard.pasteboardItems?.first)
            #expect(restored.string(forType: .string) == "original")
            #expect(restored.data(forType: customType) == original)
        }
    }

    @Test func restoringAnEmptySnapshotLeavesThePasteboardEmpty() {
        withPasteboard { pasteboard in
            pasteboard.clearContents()
            let snapshot = PasteboardSnapshot(of: pasteboard)
            pasteboard.setString("something", forType: .string)

            snapshot.restore(to: pasteboard)

            #expect(pasteboard.string(forType: .string) == nil)
            #expect((pasteboard.pasteboardItems ?? []).isEmpty)
        }
    }

    @Test func restoresWhenChangeCountIsUnchanged() {
        withPasteboard { pasteboard in
            pasteboard.clearContents()
            pasteboard.setString("user clipboard", forType: .string)
            let snapshot = PasteboardSnapshot(of: pasteboard)

            pasteboard.writeTransientString("passing through")
            snapshot.restore(to: pasteboard, ifChangeCountIs: pasteboard.changeCount)

            #expect(pasteboard.string(forType: .string) == "user clipboard")
        }
    }

    @Test func keepsWhatTheUserCopiedInBetween() {
        withPasteboard { pasteboard in
            pasteboard.clearContents()
            pasteboard.setString("old clipboard", forType: .string)
            let snapshot = PasteboardSnapshot(of: pasteboard)

            pasteboard.writeTransientString("passing through")
            let writtenCount = pasteboard.changeCount
            pasteboard.clearContents()
            pasteboard.setString("copied meanwhile", forType: .string)
            snapshot.restore(to: pasteboard, ifChangeCountIs: writtenCount)

            #expect(pasteboard.string(forType: .string) == "copied meanwhile")
        }
    }

    @Test func transientWriteMarksTheItem() throws {
        try withPasteboard { pasteboard in
            pasteboard.writeTransientString("Привет")

            let items = try #require(pasteboard.pasteboardItems)
            #expect(items.count == 1)
            #expect(items[0].string(forType: .string) == "Привет")
            #expect(items[0].types.contains(NSPasteboard.transientType))
        }
    }
}
