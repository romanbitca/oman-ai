import Foundation

/// Takes out of a result what the panel can't show but a paste would still deliver.
enum ResultCleaner {
    struct Cleaned: Equatable {
        let text: String
        let removedHiddenCharacters: Bool
    }

    /// `source` is the person's own text for a proofread or rewrite, and nil for new text.
    /// A hidden character the person already had in their text is kept.
    static func clean(_ text: String, source: String?) -> Cleaned {
        let alreadyThere = Set((source ?? "").unicodeScalars.filter(isHiddenControl))
        var kept = String.UnicodeScalarView()
        var removed = false

        for character in text {
            // The flags of England, Scotland and Wales are a black flag followed by tag characters.
            let isFlag = character.unicodeScalars.first?.value == 0x1F3F4
            for scalar in character.unicodeScalars {
                if isTagCharacter(scalar), !isFlag {
                    removed = true
                } else if isHiddenControl(scalar), !alreadyThere.contains(scalar) {
                    removed = true
                } else {
                    kept.append(scalar)
                }
            }
        }

        var cleaned = String(kept)
        // A line break the person didn't end with would run a pasted line in a terminal.
        if source?.last?.isNewline != true {
            while cleaned.last?.isNewline == true {
                cleaned.removeLast()
            }
        }
        return Cleaned(text: cleaned, removedHiddenCharacters: removed)
    }

    /// Invisible copies of ASCII, which can carry text nobody sees.
    private static func isTagCharacter(_ scalar: Unicode.Scalar) -> Bool {
        (0xE0000...0xE007F).contains(scalar.value)
    }

    private static func isHiddenControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00AD, 0x180E, 0x200B, 0x2060...0x2064, 0xFEFF:
            // Zero-width spaces and joiners that leave no mark on screen.
            true
        case 0x202A...0x202E, 0x2066...0x2069:
            // Direction overrides, which can make text read differently from what is stored.
            true
        default:
            false
        }
    }
}
