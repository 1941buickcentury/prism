import SwiftUI

/// Renders Reddit-flavored markdown as best SwiftUI can: inline styles and links,
/// plus simple handling for headings, quotes, bullets, and r/ and u/ mentions.
struct MarkdownText: View {
    let text: String

    var body: some View {
        Text(MarkdownText.render(text))
    }

    static func render(_ raw: String) -> AttributedString {
        let prepared = linkifyMentions(simplifyBlocks(raw))
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let attributed = try? AttributedString(markdown: prepared, options: options) {
            return attributed
        }
        return AttributedString(raw)
    }

    private static func simplifyBlocks(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "&#x200B;", with: "")
            .components(separatedBy: "\n")
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") {
                    let heading = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                    return heading.isEmpty ? "" : "**\(heading)**"
                }
                if trimmed.hasPrefix(">") {
                    let quote = trimmed.drop(while: { $0 == ">" }).trimmingCharacters(in: .whitespaces)
                    return "▎ *\(quote)*"
                }
                if trimmed.hasPrefix("* ") || trimmed.hasPrefix("- ") {
                    return "• " + trimmed.dropFirst(2)
                }
                if trimmed == "***" || trimmed == "---" || trimmed == "___" {
                    return "────────"
                }
                return line
            }
            .joined(separator: "\n")
    }

    private static let mentionPattern = try! NSRegularExpression(
        pattern: #"(?<![\w/\[])(/?((?:r|u)/[A-Za-z0-9_\-]{2,}))"#
    )

    private static func linkifyMentions(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return mentionPattern.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: "[$1](https://www.reddit.com/$2)"
        )
    }
}
