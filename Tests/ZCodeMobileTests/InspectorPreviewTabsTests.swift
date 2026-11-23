import XCTest
@testable import ZCode

final class InspectorPreviewTabsTests: XCTestCase {

    // MARK: - Path Resolution

    func testResolveRelativePathAgainstWorkspace() {
        XCTAssertEqual(
            InspectorPreviewPath.resolve("README.md", workspacePath: "/Users/me/app"),
            "/Users/me/app/README.md"
        )
        XCTAssertEqual(
            InspectorPreviewPath.resolve("./src/App.swift", workspacePath: "/Users/me/app/"),
            "/Users/me/app/src/App.swift"
        )
    }

    func testResolveKeepsAbsolutePathOutsideWorkspace() {
        XCTAssertEqual(
            InspectorPreviewPath.resolve("/tmp/shots/onb1.png", workspacePath: "/Users/me/app"),
            "/tmp/shots/onb1.png"
        )
        XCTAssertEqual(
            InspectorPreviewPath.resolve("/Users/macos/.zcode/logs/run.md", workspacePath: ""),
            "/Users/macos/.zcode/logs/run.md"
        )
    }

    func testResolveStripsQuotesAndFileScheme() {
        XCTAssertEqual(
            InspectorPreviewPath.resolve("`/tmp/shots/onb1.png`", workspacePath: "/Users/me/app"),
            "/tmp/shots/onb1.png"
        )
        XCTAssertEqual(
            InspectorPreviewPath.resolve("file:///tmp/a%20b.png", workspacePath: ""),
            "/tmp/a b.png"
        )
        XCTAssertEqual(
            InspectorPreviewPath.resolve("\"src/main.swift\"", workspacePath: "/w"),
            "/w/src/main.swift"
        )
    }

    func testStripsEditorLineSuffixes() {
        XCTAssertEqual(InspectorPreviewPath.normalizedInput("src/App.swift:42"), "src/App.swift")
        XCTAssertEqual(InspectorPreviewPath.normalizedInput("src/App.swift:42:7"), "src/App.swift")
        XCTAssertEqual(InspectorPreviewPath.normalizedInput("notes.md:1-20"), "notes.md")
        XCTAssertEqual(InspectorPreviewPath.normalizedInput("weird:123"), "weird:123")
    }

    // MARK: - Kind Classification

    func testKindForPath() {
        XCTAssertEqual(InspectorPreviewPath.kind(forPath: "/tmp/onb1.png"), .image)
        XCTAssertEqual(InspectorPreviewPath.kind(forPath: "spec.PDF"), .pdf)
        XCTAssertEqual(InspectorPreviewPath.kind(forPath: "README.md"), .markdown)
        XCTAssertEqual(InspectorPreviewPath.kind(forPath: "bench.csv"), .csv)
        XCTAssertEqual(InspectorPreviewPath.kind(forPath: "Sources/App.swift"), .code)
        XCTAssertEqual(InspectorPreviewPath.kind(forPath: "notes.txt"), .text)
        XCTAssertEqual(InspectorPreviewPath.kind(forPath: "bundle.zip"), .binary)
    }

    func testKindForMimeType() {
        XCTAssertEqual(InspectorPreviewPath.kind(fileName: "shot.png", mimeType: "image/png"), .image)
        XCTAssertEqual(InspectorPreviewPath.kind(fileName: "spec.pdf", mimeType: "application/pdf"), .pdf)
        XCTAssertEqual(InspectorPreviewPath.kind(fileName: "notes.md", mimeType: "text/markdown"), .markdown)
        XCTAssertEqual(InspectorPreviewPath.kind(fileName: "data.csv", mimeType: "text/csv"), .csv)
        XCTAssertEqual(InspectorPreviewPath.kind(fileName: "blob.bin", mimeType: "text/plain"), .text)
        XCTAssertEqual(InspectorPreviewPath.kind(fileName: "payload.bin", mimeType: "application/json"), .code)
        XCTAssertEqual(InspectorPreviewPath.kind(fileName: "photo.png", mimeType: "application/octet-stream"), .image)
        XCTAssertEqual(InspectorPreviewPath.kind(fileName: "report", mimeType: "application/pdf"), .pdf)
    }

    // MARK: - Tab Open / Activate / Close

    func testOpenAppendsAndActivatesNewTab() {
        var tabs = InspectorPreviewTabs()
        let first = tabs.open(InspectorPreviewTab(path: "/w/one.png"))
        XCTAssertEqual(tabs.tabs.count, 1)
        XCTAssertEqual(tabs.activeTabId, first.id)

        let second = tabs.open(InspectorPreviewTab(path: "/w/two.pdf"))
        XCTAssertEqual(tabs.tabs.count, 2)
        XCTAssertEqual(tabs.activeTabId, second.id)
        XCTAssertEqual(tabs.tabs.map(\.id), [first.id, second.id])
    }

    func testOpenExistingPathFocusesInsteadOfDuplicating() {
        var tabs = InspectorPreviewTabs()
        let first = tabs.open(InspectorPreviewTab(path: "/w/README.md"))
        _ = tabs.open(InspectorPreviewTab(path: "/w/other.txt"))
        let again = tabs.open(InspectorPreviewTab(path: "/w/./README.md"))

        XCTAssertEqual(tabs.tabs.count, 2)
        XCTAssertEqual(again.id, first.id)
        XCTAssertEqual(tabs.activeTabId, first.id)
    }

    func testOpenIsCaseInsensitiveForDeduping() {
        var tabs = InspectorPreviewTabs()
        let first = tabs.open(InspectorPreviewTab(path: "/w/Screens/Onb1.PNG"))
        _ = tabs.open(InspectorPreviewTab(path: "/w/screens/onb1.png"))
        XCTAssertEqual(tabs.tabs.count, 1)
        XCTAssertEqual(tabs.activeTabId, first.id)
    }

    func testOpenByIdFocusesDataBackedTab() {
        var tabs = InspectorPreviewTabs()
        tabs.open(InspectorPreviewTab(id: "att-1", path: "attachment://att-1/shot.png", isDataBacked: true))
        tabs.open(InspectorPreviewTab(id: "att-2", path: "attachment://att-2/notes.md"))
        let focused = tabs.open(InspectorPreviewTab(id: "att-1", path: "attachment://att-1/shot.png", isDataBacked: true))

        XCTAssertEqual(tabs.tabs.count, 2)
        XCTAssertEqual(focused.id, "att-1")
        XCTAssertEqual(tabs.activeTabId, "att-1")
        XCTAssertTrue(focused.isDataBacked)
    }

    func testCloseActiveTabPicksAdjacentTab() {
        var tabs = InspectorPreviewTabs()
        let a = tabs.open(InspectorPreviewTab(path: "/w/a.txt"))
        let b = tabs.open(InspectorPreviewTab(path: "/w/b.txt"))
        let c = tabs.open(InspectorPreviewTab(path: "/w/c.txt"))
        tabs.activate(id: b.id)

        let activeAfterClosingB = tabs.close(id: b.id)
        XCTAssertEqual(tabs.tabs.map(\.id), [a.id, c.id])
        XCTAssertEqual(activeAfterClosingB, c.id)

        let activeAfterClosingC = tabs.close(id: c.id)
        XCTAssertEqual(activeAfterClosingC, a.id)
    }

    func testCloseInactiveTabKeepsActiveTab() {
        var tabs = InspectorPreviewTabs()
        let a = tabs.open(InspectorPreviewTab(path: "/w/a.txt"))
        let b = tabs.open(InspectorPreviewTab(path: "/w/b.txt"))
        tabs.activate(id: b.id)

        tabs.close(id: a.id)
        XCTAssertEqual(tabs.activeTabId, b.id)
        XCTAssertEqual(tabs.tabs.count, 1)
    }

    func testCloseLastTabClearsActiveTab() {
        var tabs = InspectorPreviewTabs()
        let only = tabs.open(InspectorPreviewTab(path: "/w/a.txt"))
        XCTAssertEqual(tabs.close(id: only.id), "")
        XCTAssertTrue(tabs.isEmpty)
        XCTAssertNil(tabs.activeTab)
    }

    func testActivateUnknownIdIsIgnored() {
        var tabs = InspectorPreviewTabs()
        let a = tabs.open(InspectorPreviewTab(path: "/w/a.txt"))
        tabs.activate(id: "does-not-exist")
        XCTAssertEqual(tabs.activeTabId, a.id)
    }

    // MARK: - Fixture Seeding

    func testFixtureTabsKeepSelectedActiveAndIncludeRichAssets() {
        let selected = WorkspaceFileNode(
            id: "file-code", name: "App.swift", path: "src/App.swift", kind: .code,
            gitStatus: nil, sizeBytes: 10, updatedAt: Date(), textContent: "let a = 1"
        )
        let image = WorkspaceFileNode(
            id: "file-img", name: "shot.png", path: "assets/shot.png", kind: .image,
            gitStatus: nil, sizeBytes: 3, updatedAt: Date(), binaryData: Data([1, 2, 3])
        )
        let pdf = WorkspaceFileNode(
            id: "file-pdf", name: "spec.pdf", path: "assets/spec.pdf", kind: .pdf,
            gitStatus: nil, sizeBytes: 4, updatedAt: Date(), binaryData: Data([1, 2, 3, 4])
        )
        let otherCode = WorkspaceFileNode(
            id: "file-other", name: "Other.swift", path: "src/Other.swift", kind: .code,
            gitStatus: nil, sizeBytes: 2, updatedAt: Date(), textContent: "x"
        )

        let tabs = InspectorPreviewTabs.fixtureTabs(
            from: [selected, image, pdf, otherCode],
            selecting: selected.id
        )

        XCTAssertEqual(tabs.tabs.last?.workspaceNodeId, selected.id)
        XCTAssertEqual(tabs.activeTabId, tabs.tabs.last?.id)
        XCTAssertEqual(tabs.activeTab?.textContent, "let a = 1")
        XCTAssertEqual(Set(tabs.tabs.compactMap(\.workspaceNodeId)), ["file-code", "file-img", "file-pdf"])
        XCTAssertEqual(tabs.tab(matchingPath: "assets/shot.png")?.kind, .image)
        XCTAssertEqual(tabs.tab(matchingPath: "assets/shot.png")?.binaryData, Data([1, 2, 3]))
    }

    // MARK: - Data-Backed Tabs

    @MainActor
    func testOpenDataPreviewTabCreatesTextTabAndFocusesByID() {
        let store = AppStore(seedDemoWorkspace: false)
        store.openDataPreviewTab(
            id: "attachment-1",
            fileName: "notes.md",
            mimeType: "text/markdown",
            data: Data("# Hello".utf8)
        )

        XCTAssertEqual(store.previewTabs.tabs.count, 1)
        let tab = store.previewTabs.activeTab
        XCTAssertEqual(tab?.id, "attachment-1")
        XCTAssertEqual(tab?.kind, .markdown)
        XCTAssertEqual(tab?.textContent, "# Hello")
        XCTAssertEqual(tab?.displayPath, "notes.md")
        XCTAssertTrue(tab?.isDataBacked == true)
        XCTAssertEqual(store.activeInspectorTab, .preview)
        XCTAssertTrue(store.showInspectorSheet)

        store.openDataPreviewTab(
            id: "attachment-2",
            fileName: "shot.png",
            mimeType: "image/png",
            data: Data([0x89, 0x50, 0x4E, 0x47])
        )
        XCTAssertEqual(store.previewTabs.tabs.count, 2)
        XCTAssertEqual(store.previewTabs.activeTabId, "attachment-2")
        XCTAssertEqual(store.previewTabs.activeTab?.kind, .image)
        XCTAssertEqual(store.previewTabs.activeTab?.binaryData, Data([0x89, 0x50, 0x4E, 0x47]))

        // Re-opening an existing attachment id focuses its tab, no duplicate.
        store.openDataPreviewTab(
            id: "attachment-1",
            fileName: "notes.md",
            mimeType: "text/markdown",
            data: Data("# Hello".utf8)
        )
        XCTAssertEqual(store.previewTabs.tabs.count, 2)
        XCTAssertEqual(store.previewTabs.activeTabId, "attachment-1")
    }
}
