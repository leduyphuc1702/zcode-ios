import XCTest
@testable import ZCode

final class ChatFileLinkTests: XCTestCase {
    private let workspace = "/Users/me/proj"
    private let home = "/Users/me"

    private func resolve(_ href: String) -> ChatFileLink.Target? {
        ChatFileLink.resolve(href, workspacePath: workspace, homePath: home)
    }

    func testAbsoluteSystemPathsOpenAsIs() {
        XCTAssertEqual(resolve("/Users/me/Downloads/ZCode.ipa"), .init(path: "/Users/me/Downloads/ZCode.ipa", line: nil))
        XCTAssertEqual(resolve("/tmp/a%20b.txt"), .init(path: "/tmp/a b.txt", line: nil))
        XCTAssertEqual(resolve("file:///Users/me/x.md"), .init(path: "/Users/me/x.md", line: nil))
    }

    func testRelativeAndRootedPathsResolveInsideTheWorkspace() {
        XCTAssertEqual(resolve("Sources/App.swift"), .init(path: "/Users/me/proj/Sources/App.swift", line: nil))
        XCTAssertEqual(resolve("./README.md"), .init(path: "/Users/me/proj/README.md", line: nil))
        XCTAssertEqual(resolve("/src/index.ts"), .init(path: "/Users/me/proj/src/index.ts", line: nil))
        XCTAssertEqual(resolve("~/notes/a.md"), .init(path: "/Users/me/notes/a.md", line: nil))
    }

    func testLineSuffixes() {
        XCTAssertEqual(resolve("Sources/App.swift:42"), .init(path: "/Users/me/proj/Sources/App.swift", line: 42))
        XCTAssertEqual(resolve("Sources/App.swift:42:7"), .init(path: "/Users/me/proj/Sources/App.swift", line: 42))
        XCTAssertEqual(resolve("/Users/me/proj/a.ts#L10-L20"), .init(path: "/Users/me/proj/a.ts", line: 10))
    }

    func testNonFileTargetsStayInert() {
        XCTAssertNil(resolve("README.md"))
        XCTAssertNil(resolve("../outside/x.swift"))
        XCTAssertNil(resolve("https://example.com/a/b"))
        XCTAssertNil(resolve("mailto:me@example.com"))
        XCTAssertNil(resolve("~other/x"))
        XCTAssertNil(ChatFileLink.resolve("src/a.ts", workspacePath: nil, homePath: nil))
    }

    func testHomeIsDerivedFromTheWorkspace() {
        XCTAssertEqual(ChatFileLink.homePath(forWorkspace: "/Users/macos/Desktop/app"), "/Users/macos")
        XCTAssertEqual(ChatFileLink.homePath(forWorkspace: "/home/dev/app"), "/home/dev")
        XCTAssertNil(ChatFileLink.homePath(forWorkspace: "/opt/app"))
    }

    func testStandaloneImageLines() {
        XCTAssertEqual(ChatTurnCardView.markdownImage("![Chart](/Users/me/chart.png)")?.source, "/Users/me/chart.png")
        XCTAssertEqual(ChatTurnCardView.markdownImage("![](<shots/a b.png> )")?.source, "shots/a b.png")
        XCTAssertEqual(ChatTurnCardView.markdownImage("![x](https://e.com/a.png \"title\")")?.source, "https://e.com/a.png")
        XCTAssertNil(ChatTurnCardView.markdownImage("see ![x](a.png)"))
        XCTAssertNil(ChatTurnCardView.markdownImage("[link](a.png)"))
    }
}

final class CodeDocumentHighlightTests: XCTestCase {
    func testHighlightingKeepsTheTextAndColorsKeywordsAndComments() {
        let palette = SyntaxHighlighter.DocumentPalette(colors: SyntaxColors.palette(for: .githubDark))
        let source = "import SwiftUI\n// note\nlet s = \"x\""
        let doc = SyntaxHighlighter.highlightDocument(source, language: "swift", palette: palette, fontSize: 13)
        XCTAssertEqual(doc.string, source)
        XCTAssertEqual(doc.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor, palette.keyword)
        XCTAssertEqual(doc.attribute(.foregroundColor, at: 16, effectiveRange: nil) as? UIColor, palette.comment)
        let quote = (source as NSString).range(of: "\"x\"").location
        XCTAssertEqual(doc.attribute(.foregroundColor, at: quote, effectiveRange: nil) as? UIColor, palette.string)
    }

    func testLineNumbersForSelectionOffsets() {
        let view = CodeTextView()
        view.apply(style: .init(fontSize: 13, wrapLines: true, showLineNumbers: true, showsCommentIcon: true,
                                background: .black, gutterBackground: .black, gutterText: .gray, tint: .blue),
                   text: "a\nbb\n\nccc")
        view.setCode(NSAttributedString(string: "a\nbb\n\nccc"))
        XCTAssertEqual(view.lineNumber(atUTF16: 0), 1)
        XCTAssertEqual(view.lineNumber(atUTF16: 2), 2)
        XCTAssertEqual(view.lineNumber(atUTF16: 5), 3)
        XCTAssertEqual(view.lineNumber(atUTF16: 6), 4)
        XCTAssertEqual(view.lineText(2), "bb")
        XCTAssertEqual(view.lineText(4), "ccc")
    }
}
