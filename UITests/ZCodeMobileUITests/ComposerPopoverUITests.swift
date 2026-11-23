import XCTest

final class ComposerPopoverUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testContextAndModelPopoversOpen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-seed-workspace"]
        app.launch()

        let row = app.buttons["sessionRow_task-pinned-relay"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()

        let context = app.buttons["contextTelemetryButton"]
        XCTAssertTrue(context.waitForExistence(timeout: 4))
        context.tap()
        sleep(1)
        attach("context-popover")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        sleep(1)

        let model = app.buttons["composerModelPicker"]
        XCTAssertTrue(model.waitForExistence(timeout: 4))
        model.tap()
        sleep(1)
        attach("model-picker")
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
