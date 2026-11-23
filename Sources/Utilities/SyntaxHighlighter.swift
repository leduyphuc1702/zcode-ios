import SwiftUI
import Foundation

public struct SyntaxColors {
    public let plain: Color
    public let keyword: Color
    public let string: Color
    public let comment: Color
    public let type: Color
    public let number: Color
    public let function: Color
    public let attribute: Color
    public let background: Color
    public let gutterBackground: Color
    public let gutterText: Color

    public static func palette(for theme: ZCodeSyntaxTheme) -> SyntaxColors {
        switch theme {
        case .githubDark:
            return SyntaxColors(
                plain: Color(hex: 0xE6EDF3),
                keyword: Color(hex: 0xFF7B72),
                string: Color(hex: 0xA5D6FF),
                comment: Color(hex: 0x8B949E),
                type: Color(hex: 0xFFA657),
                number: Color(hex: 0x79C0FF),
                function: Color(hex: 0xD2A8FF),
                attribute: Color(hex: 0x7EE787),
                background: Color(hex: 0x16181D),
                gutterBackground: Color(hex: 0x131519),
                gutterText: Color(hex: 0x6E7681)
            )
        case .vitesseDark:
            return SyntaxColors(
                plain: Color(hex: 0xDBD7CA),
                keyword: Color(hex: 0x4D9375),
                string: Color(hex: 0xC98A7D),
                comment: Color(hex: 0x758575),
                type: Color(hex: 0x5DA994),
                number: Color(hex: 0x4C9A91),
                function: Color(hex: 0x80A665),
                attribute: Color(hex: 0xBD976A),
                background: Color(hex: 0x121212),
                gutterBackground: Color(hex: 0x0E0E0E),
                gutterText: Color(hex: 0x585858)
            )
        case .catppuccinMocha:
            return SyntaxColors(
                plain: Color(hex: 0xCDD6F4),
                keyword: Color(hex: 0xCBA6F7),
                string: Color(hex: 0xA6E3A1),
                comment: Color(hex: 0x6C7086),
                type: Color(hex: 0xF9E2AF),
                number: Color(hex: 0xFAB387),
                function: Color(hex: 0x89B4FA),
                attribute: Color(hex: 0x94E2D5),
                background: Color(hex: 0x1E1E2E),
                gutterBackground: Color(hex: 0x181825),
                gutterText: Color(hex: 0x6C7086)
            )
        case .githubLight:
            return SyntaxColors(
                plain: Color(hex: 0x1F2328),
                keyword: Color(hex: 0xCF222E),
                string: Color(hex: 0x0A3069),
                comment: Color(hex: 0x6E7781),
                type: Color(hex: 0x953800),
                number: Color(hex: 0x0550AE),
                function: Color(hex: 0x8250DF),
                attribute: Color(hex: 0x116329),
                background: Color(hex: 0xFFFFFF),
                gutterBackground: Color(hex: 0xF6F8FA),
                gutterText: Color(hex: 0x8C959F)
            )
        case .vitesseLight:
            return SyntaxColors(
                plain: Color(hex: 0x393A34),
                keyword: Color(hex: 0x1E754F),
                string: Color(hex: 0xB56959),
                comment: Color(hex: 0xA0ADA0),
                type: Color(hex: 0x2E8F82),
                number: Color(hex: 0x2F798A),
                function: Color(hex: 0x59873A),
                attribute: Color(hex: 0x998418),
                background: Color(hex: 0xFFFFFF),
                gutterBackground: Color(hex: 0xF7F7F7),
                gutterText: Color(hex: 0x999999)
            )
        case .catppuccinLatte:
            return SyntaxColors(
                plain: Color(hex: 0x4C4F69),
                keyword: Color(hex: 0x8839EF),
                string: Color(hex: 0x40A02B),
                comment: Color(hex: 0x8C8FA1),
                type: Color(hex: 0xDF8E1D),
                number: Color(hex: 0xFE640B),
                function: Color(hex: 0x1E66F5),
                attribute: Color(hex: 0x179299),
                background: Color(hex: 0xEFF1F5),
                gutterBackground: Color(hex: 0xE6E9EF),
                gutterText: Color(hex: 0x8C8FA1)
            )
        }
    }
}

/// Pure native Swift syntax highlighter producing AttributedString without WebKit/JS.
public enum SyntaxHighlighter {
    private static let keywords: Set<String> = [
        "import", "func", "let", "var", "struct", "class", "enum", "protocol", "extension",
        "public", "private", "internal", "fileprivate", "open", "static", "final", "return",
        "if", "else", "switch", "case", "default", "for", "while", "guard", "in", "where",
        "async", "await", "throws", "try", "catch", "throw", "defer", "init", "self", "Self",
        "true", "false", "nil", "null", "undefined", "const", "function", "export", "from",
        "interface", "type", "implements", "extends", "new", "this", "super", "def", "lambda",
        "yield", "with", "as", "match", "fn", "pub", "mut", "impl", "trait", "use", "mod",
        "crate", "package", "val", "when", "object", "companion", "suspend", "actor", "some", "any"
    ]

    public static func highlightLine(
        _ line: String,
        language: String,
        theme: ZCodeSyntaxTheme,
        fontSize: CGFloat,
        searchQuery: String = ""
    ) -> AttributedString {
        let colors = SyntaxColors.palette(for: theme)
        var result = AttributedString(line.isEmpty ? " " : line)
        result.font = .system(size: fontSize, weight: .regular, design: .monospaced)
        result.foregroundColor = colors.plain

        guard !line.isEmpty else { return result }

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") || (trimmed.hasPrefix("#") && language != "markdown") || trimmed.hasPrefix("--") {
            result.foregroundColor = colors.comment
            applySearchHighlight(to: &result, in: line, query: searchQuery)
            return result
        }

        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)

        // Annotations / decorators (@MainActor, @Observable, @State)
        applyRegex("@[A-Za-z_][A-Za-z0-9_]*", color: colors.attribute, in: line, nsLine: nsLine, range: fullRange, to: &result)
        // Numbers
        applyRegex("\\b\\d+(\\.\\d+)?\\b", color: colors.number, in: line, nsLine: nsLine, range: fullRange, to: &result)
        // Uppercase Identifiers / Types
        applyRegex("\\b[A-Z][A-Za-z0-9_]*\\b", color: colors.type, in: line, nsLine: nsLine, range: fullRange, to: &result)
        // Function calls
        applyRegex("\\b[a-z_][A-Za-z0-9_]*(?=\\s*\\()", color: colors.function, in: line, nsLine: nsLine, range: fullRange, to: &result)

        // Keywords
        if let wordRegex = try? NSRegularExpression(pattern: "\\b[A-Za-z_][A-Za-z0-9_]*\\b") {
            for match in wordRegex.matches(in: line, range: fullRange) {
                let word = nsLine.substring(with: match.range)
                if keywords.contains(word),
                   let swiftRange = Range(match.range, in: line),
                   let attrRange = Range(swiftRange, in: result) {
                    result[attrRange].foregroundColor = colors.keyword
                    result[attrRange].font = .system(size: fontSize, weight: .semibold, design: .monospaced)
                }
            }
        }

        // Strings (override inside quotes)
        applyRegex("\"([^\"\\\\]|\\\\.)*\"|'([^'\\\\]|\\\\.)*'|`([^`\\\\]|\\\\.)*`", color: colors.string, in: line, nsLine: nsLine, range: fullRange, to: &result)

        // Trailing inline comments
        applyRegex("//.*$", color: colors.comment, in: line, nsLine: nsLine, range: fullRange, to: &result)

        applySearchHighlight(to: &result, in: line, query: searchQuery)
        return result
    }

    private static func applyRegex(
        _ pattern: String,
        color: Color,
        in line: String,
        nsLine: NSString,
        range: NSRange,
        to result: inout AttributedString
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        for match in regex.matches(in: line, range: range) {
            if let swiftRange = Range(match.range, in: line),
               let attrRange = Range(swiftRange, in: result) {
                result[attrRange].foregroundColor = color
            }
        }
    }

    private static func applySearchHighlight(to result: inout AttributedString, in line: String, query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        var searchStart = line.startIndex
        while searchStart < line.endIndex,
              let found = line.range(of: q, options: [.caseInsensitive], range: searchStart..<line.endIndex) {
            if let attrRange = Range(found, in: result) {
                result[attrRange].backgroundColor = Color(hex: 0xF59E0B).opacity(0.42)
                result[attrRange].foregroundColor = Color.white
            }
            searchStart = found.upperBound
        }
    }

    public static func detectLanguage(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "ts", "tsx": return "typescript"
        case "js", "jsx", "mjs": return "javascript"
        case "py": return "python"
        case "rs": return "rust"
        case "go": return "go"
        case "kt", "kts": return "kotlin"
        case "json": return "json"
        case "yml", "yaml": return "yaml"
        case "md", "markdown": return "markdown"
        case "sh", "zsh", "bash": return "shell"
        case "sql": return "sql"
        case "css", "scss": return "css"
        case "html": return "html"
        default: return "code"
        }
    }
}
