import XCTest

final class ChatLinksAndCodeSelectionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFileLinksImagesAndRangeSelectionInCode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-seed-workspace"]
        app.launch()

        let row = app.buttons["sessionRow_task-rpc-refactor"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()

        // The inline image renders in the transcript and opens the preview pane.
        let image = app.buttons["chatMarkdownImage"]
        XCTAssertTrue(image.waitForExistence(timeout: 5), "standalone markdown image must render")
        shot("chat-link-and-image")
        image.tap()
        XCTAssertTrue(app.otherElements["inspectorBackdrop"].waitForExistence(timeout: 4), "tapping the image must open the preview pane")
        shot("image-preview")
        app.otherElements["inspectorBackdrop"].coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).tap()

        // A markdown file link opens that file in the preview pane.
        let link = app.links["RelayMultiplexer.ts"]
        XCTAssertTrue(link.waitForExistence(timeout: 4), "file link must be a tappable link")
        link.tap()
        XCTAssertTrue(app.otherElements["inspectorBackdrop"].waitForExistence(timeout: 4), "tapping a file link must open the preview pane")
        let code = app.textViews.containing(NSPredicate(format: "value CONTAINS 'RelayMultiplexer'")).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 5), "file text must show in the code canvas")
        shot("file-link-preview")

        // Long-press and drag selects a range spanning several lines.
        code.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.03))
            .press(forDuration: 0.8, thenDragTo: code.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.2)))
        XCTAssertTrue(app.otherElements["inspectorBackdrop"].exists, "a selection drag must not swipe the pane closed")
        XCTAssertTrue(app.menuItems["Copy"].waitForExistence(timeout: 3), "edit menu must appear after a drag selection")
        // Pull the end handle (after "number;" on line 7) down several lines.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.657, dy: 0.395))
            .press(forDuration: 0.3, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)))
        XCTAssertTrue(app.otherElements["inspectorBackdrop"].exists)
        XCTAssertTrue(app.menuItems["Copy"].waitForExistence(timeout: 3))
        shot("multi-line-selection")
        app.menuItems["Copy"].tap()
        let range = pastedIntoComposer(app)
        XCTAssertGreaterThanOrEqual(range.components(separatedBy: "\n").count, 3, "dragging the handle must select across lines, got: \(range)")
        dismissKeyboard(app)

        // Long-press alone selects one word, not the whole line.
        app.links["RelayMultiplexer.ts"].tap()
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        code.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.08)).press(forDuration: 0.8)
        XCTAssertTrue(app.menuItems["Copy"].waitForExistence(timeout: 3), "edit menu must appear on long-press")
        shot("word-selection")
        app.menuItems["Copy"].tap()
        let word = pastedIntoComposer(app)
        XCTAssertFalse(word.isEmpty)
        XCTAssertFalse(word.contains("\n"), "a long-press should copy a word, got: \(word)")
        XCTAssertLessThan(word.count, 40, "a long-press should copy a word, got: \(word)")
        dismissKeyboard(app)

        // Files tab: same canvas with the comment gutter; tapping a line number starts a line comment.
        app.links["RelayMultiplexer.ts"].tap()
        let filesTab = app.buttons["inspectorTab_files"]
        XCTAssertTrue(filesTab.waitForExistence(timeout: 4))
        filesTab.tap()
        let filesCode = app.textViews.containing(NSPredicate(format: "value CONTAINS 'RelayMultiplexer'")).firstMatch
        XCTAssertTrue(filesCode.waitForExistence(timeout: 5))
        shot("files-tab-code")
        filesCode.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.0)).withOffset(CGVector(dx: 6, dy: 60)).tap()
        XCTAssertTrue(app.alerts["Add Inline Code Comment"].waitForExistence(timeout: 3), "tapping a line number must start a comment")
        shot("line-comment")
        app.alerts.buttons["Cancel"].tap()
    }

    private func dismissKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.tap() : app.staticTexts["Task chat"].tap()
    }

    /// Closes the preview pane and pastes the clipboard into the composer, returning what landed there.
    private func pastedIntoComposer(_ app: XCUIApplication) -> String {
        app.otherElements["inspectorBackdrop"].coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).tap()
        let composer = app.textFields["composerTextField"].exists ? app.textFields["composerTextField"] : app.textViews["composerTextField"]
        XCTAssertTrue(composer.waitForExistence(timeout: 4))
        composer.tap()
        composer.press(forDuration: 1.0)
        let paste = app.menuItems["Paste"]
        guard paste.waitForExistence(timeout: 3) else { return "" }
        paste.tap()
        let value = (composer.value as? String) ?? ""
        composer.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) {
            app.menuItems["Select All"].tap()
            composer.typeText(XCUIKeyboardKey.delete.rawValue)
        }
        return value
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
