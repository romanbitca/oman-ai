import Foundation
import NaturalLanguage

/// What a set of messages shows about capital letters, full stops and apostrophes.
///
/// Proofread needs this to tell a habit from a mistake. It is counted here, in code, because a model asked to
/// work it out from the samples while it writes got it wrong in about half of its answers.
struct WritingHabits: Equatable {
    enum Apostrophes: Equatable {
        case written, leftOut, unknown
    }

    /// Whether most sentences start with a lower-case letter and "i" is mostly written small.
    /// Nil when the messages show neither, as in a script that has no capital letters.
    let startsSentencesInLowerCase: Bool?
    /// Most one-line messages end without a full stop.
    let leavesOutFinalFullStop: Bool
    let apostrophes: Apostrophes

    init(of texts: [String]) {
        var lower = 0
        var upper = 0
        var withoutStop = 0
        var withStop = 0
        for text in texts {
            let starts = Self.sentenceStarts(in: text)
            lower += starts.lower
            upper += starts.upper

            // An email ends with a name, not a sentence, so only one-line messages say how a message ends.
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.contains(where: \.isNewline), let last = trimmed.last else { continue }
            if last == "." {
                withStop += 1
            } else if last.isLetter || last.isNumber {
                withoutStop += 1
            }
        }
        startsSentencesInLowerCase = lower + upper == 0 ? nil : lower > upper
        leavesOutFinalFullStop = withoutStop > withStop
        apostrophes = Self.apostrophes(in: texts)
    }

    private enum Position {
        case start, inside, afterEnd
    }

    /// Counts the first letter of each sentence and each "i" that stands alone.
    private static func sentenceStarts(in text: String) -> (lower: Int, upper: Int) {
        var lower = 0
        var upper = 0
        var position = Position.start
        var previous: Character = " "
        let characters = Array(text)

        for (index, character) in characters.enumerated() {
            defer { previous = character }

            if character == "i" || character == "I", !previous.isLetter, !previous.isNumber {
                let next = index + 1 < characters.count ? characters[index + 1] : " "
                // Alone, or the start of i'm and i'll. The sentence count below sees it too when it opens a sentence.
                if !next.isLetter, !next.isNumber, position != .start {
                    if character == "i" { lower += 1 } else { upper += 1 }
                }
            }

            switch position {
            case .start:
                if character.isLetter {
                    if character.isLowercase { lower += 1 } else if character.isUppercase { upper += 1 }
                    position = .inside
                } else if character.isNumber {
                    // A sentence that opens with a number says nothing about capitals.
                    position = .inside
                }
            case .inside:
                if character.isNewline {
                    position = .start
                } else if ".!?…".contains(character) {
                    position = .afterEnd
                }
            case .afterEnd:
                if character.isWhitespace {
                    position = .start
                } else if !".!?…\"')”’".contains(character) {
                    // A full stop inside a word, as in example.com or 3.5, ends nothing.
                    position = .inside
                }
            }
        }
        return (lower, upper)
    }

    /// Contractions that are no word of their own without the apostrophe, so finding one means it was left out.
    private static let bareContractions: Set<String> = [
        "dont", "cant", "im", "ive", "thats", "isnt", "arent", "wasnt", "werent", "didnt", "doesnt", "havent",
        "hasnt", "wouldnt", "couldnt", "shouldnt", "youre", "theyre", "whats", "theres", "youll", "theyll",
        "weve", "youve", "theyve",
    ]

    private static func apostrophes(in texts: [String]) -> Apostrophes {
        let joined = texts.joined(separator: "\n")
        let characters = Array(joined)
        for index in characters.indices.dropFirst().dropLast()
        where (characters[index] == "'" || characters[index] == "\u{2019}")
            && characters[index - 1].isLetter && characters[index + 1].isLetter {
            return .written
        }
        // The list is English, so it only counts as evidence in English text.
        guard TextLanguage.code(of: joined) == "en" else { return .unknown }
        let words = joined.lowercased().split { !$0.isLetter }.map(String.init)
        return words.contains(where: bareContractions.contains) ? .leftOut : .unknown
    }
}

/// Tells which language a text is written in, on this Mac and without sending it anywhere.
enum TextLanguage {
    /// A language code such as "en", or nil when the text is too short or too mixed to tell.
    static func code(of text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let best = recognizer.languageHypotheses(withMaximum: 1).first, best.value >= 0.6,
              best.key != .undetermined else { return nil }
        return best.key.rawValue
    }

    /// The language's English name, such as "Romanian", for use in a prompt.
    static func name(of text: String) -> String? {
        guard let code = code(of: text) else { return nil }
        return Locale(identifier: "en_US").localizedString(forIdentifier: code)
    }
}
