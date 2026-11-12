import Foundation

/// What is done to dictated words before they are shown and put in: hesitations taken out, and the person's own
/// words, such as names, spelled their way.
public enum DictationText {
    /// Sounds people make while thinking, in the languages OmanAI's models know best. Taken out only where they
    /// stand alone as a word, so "umbrella" or "errand" are never touched.
    static let fillers: Set<String> = [
        "um", "umm", "uh", "uhh", "uhm", "erm", "er", "err", "ah", "ahh", "hmm", "hm", "mm", "mmm", "eh",
        "э", "ээ", "эээ", "эм", "мм", "ммм", "а-а", "ăă", "ăăă", "îî", "îîî",
    ]

    public static func removingFillers(from text: String) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        var kept: [Substring] = []
        for word in words {
            let bare = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if fillers.contains(bare) {
                // A filler that ended a sentence hands its full stop to the word before it.
                if let mark = word.last, ".?!".contains(mark), let previous = kept.popLast() {
                    let trimmed = previous.trimmingCharacters(in: CharacterSet(charactersIn: ","))
                    kept.append(Substring(trimmed + String(mark)))
                }
                continue
            }
            kept.append(word)
        }
        var result = kept.joined(separator: " ")
        if let first = result.first, let original = text.trimmingCharacters(in: .whitespaces).first,
           original.isUppercase, first.isLowercase {
            // The sentence started with a filler, so the new first word gets its capital.
            result = first.uppercased() + result.dropFirst()
        }
        return result
    }

    /// Replaces what the model wrote for one of `words` with the word as the person spells it. A match ignores case,
    /// spaces and punctuation, so "axia pos" becomes "AxiaPOS", and words of five letters or more also match when
    /// a letter or two differ, so "Axiapose" does too. Up to three words in a row can make one match.
    public static func applying(_ words: [String], to text: String) -> String {
        let wanted = words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !wanted.isEmpty, !text.isEmpty else { return text }
        var tokens = tokenize(text)
        var index = 0
        while index < tokens.count {
            guard tokens[index].isWord, let match = bestMatch(at: index, in: tokens, for: wanted) else {
                index += 1
                continue
            }
            // The span runs over `match.length` words and the spaces between them.
            var end = index
            var counted = 0
            while end < tokens.count {
                if tokens[end].isWord { counted += 1 }
                if counted == match.length { break }
                end += 1
            }
            tokens.replaceSubrange(index...end, with: [Token(text: match.word, isWord: true)])
            index += 1
        }
        return tokens.map(\.text).joined()
    }

    struct Token: Equatable {
        let text: String
        let isWord: Bool
    }

    /// Words, and everything between them, in order: joined again they give back the text.
    static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var inWord = false
        for character in text {
            let isWordCharacter = character.isLetter || character.isNumber
                || (inWord && (character == "'" || character == "’"))
            if isWordCharacter != inWord, !current.isEmpty {
                tokens.append(Token(text: current, isWord: inWord))
                current = ""
            }
            inWord = isWordCharacter
            current.append(character)
        }
        if !current.isEmpty {
            tokens.append(Token(text: current, isWord: inWord))
        }
        return tokens
    }

    private static func normalized(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// The custom word that the words starting at `index` stand for, and how many words it takes up.
    private static func bestMatch(at index: Int, in tokens: [Token], for words: [String]) -> (word: String, length: Int)? {
        var spoken: [String] = []
        var position = index
        var best: (word: String, length: Int, score: Double)?
        while position < tokens.count, spoken.count < 3 {
            let token = tokens[position]
            if token.isWord {
                spoken.append(normalized(token.text))
                let joined = spoken.joined()
                for word in words {
                    let target = normalized(word)
                    guard !target.isEmpty else { continue }
                    let score = similarity(joined, target)
                    let isClose = target.count >= 5 && joined.first == target.first && score >= 0.8
                    if joined == target || isClose, score > (best?.score ?? 0) {
                        best = (word, spoken.count, score)
                    }
                }
            } else if !token.text.allSatisfy({ $0 == " " }) {
                // Punctuation ends the run: "Axia. Pos" is two sentences, not a name.
                break
            }
            position += 1
        }
        guard let best else { return nil }
        // Already spelled the person's way.
        if best.length == 1, tokens[index].text == best.word { return nil }
        return (best.word, best.length)
    }

    /// 1 for the same letters, falling toward 0 the more letters must change, by edit distance.
    static func similarity(_ first: String, _ second: String) -> Double {
        let a = Array(first)
        let b = Array(second)
        guard !a.isEmpty || !b.isEmpty else { return 1 }
        var previous = Array(0...b.count)
        for (i, left) in a.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, right) in b.enumerated() {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (left == right ? 0 : 1))
            }
            previous = current
        }
        return 1 - Double(previous[b.count]) / Double(max(a.count, b.count))
    }
}
