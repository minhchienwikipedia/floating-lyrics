import Foundation
import SwiftUI

/// Generates furigana (hiragana readings) for kanji using macOS's built-in Japanese tokenizer.
enum Furigana {
    struct Segment: Hashable {
        let base: String
        let ruby: String?
    }

    private static var cache: [String: [Segment]] = [:]
    private static var noKanji: Set<String> = []

    /// Segments for `text`, or nil when it has no kanji (render it as plain text).
    static func segments(for text: String) -> [Segment]? {
        if noKanji.contains(text) { return nil }
        if let cached = cache[text] { return cached }
        guard text.unicodeScalars.contains(where: isKanji) else {
            noKanji.insert(text)
            return nil
        }
        let result = tokenize(text)
        cache[text] = result
        return result
    }

    private static func tokenize(_ text: String) -> [Segment] {
        let ns = text as NSString
        let tokenizer = CFStringTokenizerCreate(nil, ns, CFRange(location: 0, length: ns.length),
                                                kCFStringTokenizerUnitWord, Locale(identifier: "ja") as CFLocale)
        var segments: [Segment] = []
        var cursor = 0

        while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            if range.location > cursor {   // spaces / punctuation the tokenizer skipped
                segments.append(Segment(base: ns.substring(with: NSRange(location: cursor, length: range.location - cursor)), ruby: nil))
            }
            let token = ns.substring(with: NSRange(location: range.location, length: range.length))
            if token.unicodeScalars.contains(where: isKanji),
               let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String,
               let reading = latin.applyingTransform(.latinToHiragana, reverse: false) {
                segments.append(contentsOf: split(token, reading: reading))
            } else {
                segments.append(Segment(base: token, ruby: nil))
            }
            cursor = range.location + range.length
        }
        if cursor < ns.length {
            segments.append(Segment(base: ns.substring(from: cursor), ruby: nil))
        }
        return segments
    }

    /// Puts the reading only over the kanji part: kana shared at the start/end
    /// (okurigana like the った in 持った) is shown without ruby.
    private static func split(_ token: String, reading: String) -> [Segment] {
        var base = Array(token)
        var ruby = Array(reading)
        var prefix = "", suffix = ""

        func hira(_ c: Character) -> Character {
            String(c).applyingTransform(.hiraganaToKatakana, reverse: true)?.first ?? c
        }
        while let b = base.last, let r = ruby.last, !isKanji(b), hira(b) == r, base.count > 1 {
            suffix = String(b) + suffix
            base.removeLast(); ruby.removeLast()
        }
        while let b = base.first, let r = ruby.first, !isKanji(b), hira(b) == r, base.count > 1 {
            prefix += String(b)
            base.removeFirst(); ruby.removeFirst()
        }

        let core = String(base), coreRuby = String(ruby)
        var result: [Segment] = []
        if !prefix.isEmpty { result.append(Segment(base: prefix, ruby: nil)) }
        let sameAsBase = core.applyingTransform(.hiraganaToKatakana, reverse: true) == coreRuby
        result.append(Segment(base: core, ruby: coreRuby.isEmpty || sameAsBase ? nil : coreRuby))
        if !suffix.isEmpty { result.append(Segment(base: suffix, ruby: nil)) }
        return result
    }

    private static func isKanji(_ c: Character) -> Bool {
        c.unicodeScalars.contains(where: isKanji)
    }

    private static func isKanji(_ s: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(s.value) || (0x3400...0x4DBF).contains(s.value) || s.value == 0x3005 // 々
    }
}

/// Lays out pieces left-to-right, wrapping to new rows, with each row aligned.
struct FlowLayout: Layout {
    var alignment: TextAlignment = .center

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.reduce(0) { $0 + $1.height })
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(maxWidth: bounds.width, subviews: subviews) {
            var x: CGFloat
            switch alignment {
            case .leading: x = bounds.minX
            case .trailing: x = bounds.maxX - row.width
            default: x = bounds.minX + (bounds.width - row.width) / 2
            }
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + row.height - size.height),
                                  anchor: .topLeading, proposal: .unspecified)
                x += size.width
            }
            y += row.height
        }
    }

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for (i, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if rows[rows.count - 1].width + size.width > maxWidth, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            rows[rows.count - 1].indices.append(i)
            rows[rows.count - 1].width += size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
