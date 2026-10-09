import Foundation

/// A localized count phrase split around its number, so the number can be set large
/// while the words still agree with it: "1 day in a row", "5 дней подряд", "连续 5 天".
/// The words cannot be translated on their own — a plural form has to carry the
/// number — so the whole phrase is translated and then cut where the number sits.
struct CountPhrase: Equatable {
    let before: String
    let number: String
    let after: String

    init(_ phrase: String, count: Int) {
        let candidates = [count.formatted(), String(count)]
        guard let range = candidates.lazy.compactMap({ phrase.range(of: $0) }).first else {
            before = ""
            number = String(count)
            after = phrase
            return
        }
        before = phrase[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        number = String(phrase[range])
        after = phrase[range.upperBound...].trimmingCharacters(in: .whitespaces)
    }
}

extension CountPhrase {
    /// The phrase back in one piece, for VoiceOver and for plain text.
    var joined: String {
        [before, number, after].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
