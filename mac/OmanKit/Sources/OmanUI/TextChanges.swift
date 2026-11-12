import Foundation

/// What differs between the person's text and a corrected one, word by word.
/// Worked out on the Mac from the two texts, so showing it sends nothing anywhere.
struct TextChanges: Equatable, Sendable {
    enum Piece: Equatable, Sendable {
        /// In both texts.
        case same(String)
        /// Only in the original.
        case removed(String)
        /// Only in the corrected text.
        case added(String)

        var text: String {
            switch self {
            case .same(let text), .removed(let text), .added(let text): text
            }
        }

        var isSame: Bool {
            if case .same = self { return true }
            return false
        }

        /// False for a piece of spacing alone.
        var hasText: Bool { text.contains { !$0.isWhitespace } }
    }

    /// In reading order. What was removed comes just before what replaced it.
    /// The same and removed pieces spell the original; the same and added pieces spell the corrected text.
    let pieces: [Piece]
    /// How many places differ. A word swapped for another counts once, and a change of spacing alone is not counted.
    let count: Int
    /// True when more than half of the words differ in a text of some length. Marks would then cover everything
    /// and say nothing, so the panel offers the original to read instead.
    let isRewrite: Bool

    init(from original: String, to corrected: String) {
        let old = Self.tokens(of: original)
        let new = Self.tokens(of: corrected)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in new.difference(from: old) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var pieces: [Piece] = []
        func append(_ piece: Piece) {
            switch (pieces.last, piece) {
            case (.same(let before), .same(let text)): pieces[pieces.count - 1] = .same(before + text)
            case (.removed(let before), .removed(let text)): pieces[pieces.count - 1] = .removed(before + text)
            case (.added(let before), .added(let text)): pieces[pieces.count - 1] = .added(before + text)
            default: pieces.append(piece)
            }
        }
        var oldIndex = 0
        var newIndex = 0
        var changedWords = 0
        while oldIndex < old.count || newIndex < new.count {
            if oldIndex < old.count, removed.contains(oldIndex) {
                if Self.isWord(old[oldIndex]) { changedWords += 1 }
                append(.removed(String(old[oldIndex])))
                oldIndex += 1
            } else if newIndex < new.count, inserted.contains(newIndex) {
                if Self.isWord(new[newIndex]) { changedWords += 1 }
                append(.added(String(new[newIndex])))
                newIndex += 1
            } else if newIndex < new.count {
                append(.same(String(new[newIndex])))
                oldIndex += 1
                newIndex += 1
            } else {
                // Cannot happen: every old token that is left is either removed or matched by a new one.
                break
            }
        }
        self.pieces = pieces

        // Pieces that differ with nothing the same between them are one change.
        var count = 0
        var isCounted = false
        for piece in pieces {
            if piece.isSame {
                isCounted = false
            } else if !isCounted, piece.hasText {
                count += 1
                isCounted = true
            }
        }
        self.count = count

        let words = old.count(where: Self.isWord) + new.count(where: Self.isWord)
        isRewrite = words >= 16 && changedWords * 2 > words
    }

    /// The text cut into words, runs of spacing, and single marks. Joined again, the pieces spell the text exactly.
    static func tokens(of text: String) -> [Substring] {
        var tokens: [Substring] = []
        var start = text.startIndex
        var index = text.startIndex
        var kind: Kind?

        func close(at end: String.Index) {
            if start < end { tokens.append(text[start..<end]) }
            start = end
        }

        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            let current: Kind
            if character.isWhitespace {
                current = .spacing
            } else if isWordCharacter(character) {
                current = .word
            } else if kind == .word, isApostrophe(character), next < text.endIndex, isWordCharacter(text[next]) {
                // The apostrophe in "don't" belongs to the word.
                current = .word
            } else {
                current = .mark
            }
            if current != kind || current == .mark {
                close(at: index)
                kind = current
            }
            index = next
        }
        close(at: text.endIndex)
        return tokens
    }

    private enum Kind { case word, spacing, mark }

    private static func isWord(_ token: Substring) -> Bool {
        guard let first = token.first else { return false }
        return first.isLetter || first.isNumber
    }

    private static func isApostrophe(_ character: Character) -> Bool {
        character == "'" || character == "\u{2019}"
    }

    /// Letters and digits make words. In scripts written without spaces between words, each character
    /// stands alone, so one corrected character does not mark the whole sentence.
    private static func isWordCharacter(_ character: Character) -> Bool {
        guard character.isLetter || character.isNumber, let scalar = character.unicodeScalars.first else { return false }
        if scalar.properties.isIdeographic { return false }
        switch scalar.value {
        case 0x3040...0x30FF, 0x31F0...0x31FF: return false // Hiragana and Katakana
        case 0x0E00...0x0EFF: return false // Thai and Lao
        case 0x1000...0x109F, 0x1780...0x17FF: return false // Myanmar and Khmer
        default: return true
        }
    }
}
