import XCTest

final class ZCodeMobileE2EUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test01ProductionFreshInstallOnboardingAndZaiRemoteFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-reset-onboarding"]
        app.launch()

        // 1. Assert Zero Demo Screens & Verify Step 1: Z.AI Account Sign-In
        let signInBtn = app.buttons["signInWithZaiButton"]
        XCTAssertTrue(signInBtn.waitForExistence(timeout: 8), "Production fresh launch must show Step 1 Sign in with Z.AI")
        XCTAssertTrue(app.staticTexts["STEP 1 OF 2"].exists)
        XCTAssertTrue(app.staticTexts["Sign in to ZCode Remote"].exists)
        XCTAssertFalse(app.staticTexts["Macs-Mac-mini.local"].exists, "Zero demo workstations allowed in Production")
        XCTAssertFalse(app.buttons["sessionRow_task-rpc-refactor"].exists, "Zero demo tasks allowed in Production")
        saveScreenshot(name: "00a-Production-Step1-Zai-SignIn")

        // Expand Access Token login option to verify native layout
        let tokenToggle = app.buttons["toggleZaiTokenLoginButton"]
        XCTAssertTrue(tokenToggle.exists)
        tokenToggle.tap()
        XCTAssertTrue(app.secureTextFields["zaiAccessTokenField"].waitForExistence(timeout: 3))
        saveScreenshot(name: "00b-Production-Step1-Token-Option")

        // 2. Advance to Step 2: Enter Z.AI Remote Link / Scan QR
        let skipBtn = app.buttons["skipToRemoteLinkStepButton"]
        XCTAssertTrue(skipBtn.exists)
        skipBtn.tap()

        let urlField = app.textFields["remoteURLTextField"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 4), "Step 2 Z.AI Remote URL field must exist")
        XCTAssertTrue(app.staticTexts["Connect Z.AI Remote Control"].exists)
        XCTAssertTrue(app.buttons["pasteRemoteURLButton"].exists)
        XCTAssertTrue(app.buttons["onboardingScanQRButton"].exists)
        XCTAssertTrue(app.buttons["returnToZaiSignInButton"].exists)
        saveScreenshot(name: "00c-Production-Step2-Enter-Zai-Remote-Link")

        // 3. Open Native QR Scanner Sheet & Verify
        app.buttons["onboardingScanQRButton"].tap()
        let closeQR = app.buttons["closeQRScannerButton"]
        XCTAssertTrue(closeQR.waitForExistence(timeout: 4))
        saveScreenshot(name: "00d-Production-QR-Scanner-Sheet")
        closeQR.tap()

        // 4. Enter Z.AI Remote V4 Link & Verify Live Validation Badge
        urlField.tap()
        urlField.typeText("https://zcode.z.ai/remote/v4?sid=sid_prod_01&mid=mid_prod_01&name=Studio-MacBook#hash99")
        XCTAssertTrue(app.staticTexts["Z.AI Remote Control • Studio-MacBook"].waitForExistence(timeout: 3))
        saveScreenshot(name: "00e-Production-Step2-Validated-Remote-Link")

        // 5. Tap Connect -> Verify 4-Step ZCode Relay Pairing Overlay
        let connectBtn = app.buttons["connectRemoteLinkButton"]
        XCTAssertTrue(connectBtn.isEnabled)
        connectBtn.tap()

        let cancelOrEditBtn = app.buttons["cancelOrDismissPairingButton"]
        XCTAssertTrue(cancelOrEditBtn.waitForExistence(timeout: 5), "4-step Relay Pairing overlay must appear")
        XCTAssertTrue(app.staticTexts["Connect to relay service"].exists)
        XCTAssertTrue(app.staticTexts["Authenticate terminal"].exists)
        XCTAssertTrue(app.staticTexts["Pair with ZCode Desktop"].exists)
        XCTAssertTrue(app.staticTexts["Sync workspaces & tasks"].exists)
        saveScreenshot(name: "00f-Production-Relay-Pairing-Steps")

        cancelOrEditBtn.tap()
        XCTAssertTrue(app.staticTexts["Saved Connections"].waitForExistence(timeout: 4), "Entered link must be persisted under Saved Connections")
        saveScreenshot(name: "00g-Production-Saved-Connections")
    }

    @MainActor
    func test02CompleteEnterpriseWorkspaceFlowsWithFixture() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-seed-workspace"]
        app.launch()

        // 1. Verify ZCode Remote Home Screen (English Default)
        let newSessionBtn = app.buttons["newSessionButton"]
        XCTAssertTrue(newSessionBtn.waitForExistence(timeout: 8), "ZCode Remote Home New task row must exist")
        XCTAssertTrue(app.staticTexts["Task list"].exists, "Task list header must render in English")
        XCTAssertTrue(app.staticTexts["Pinned"].exists, "Pinned section must render")
        XCTAssertTrue(app.staticTexts["Projects"].exists, "Projects section must render")
        saveScreenshot(name: "01-ZCode-Remote-Home")

        // 2. Open Running Pinned Task to Verify 1:1 Prompt Queue ("↑ Steer") + Stop Button + Floating Todo Pill
        let runningPinnedRow = app.buttons["sessionRow_task-pinned-relay"]
        XCTAssertTrue(runningPinnedRow.waitForExistence(timeout: 4))
        runningPinnedRow.tap()

        let steerBtn = app.buttons["steerQueuedPromptButton"]
        XCTAssertTrue(steerBtn.waitForExistence(timeout: 4), "Nested ↑ Steer pill button must render on queued prompt")
        XCTAssertTrue(app.buttons["editQueuedPromptButton"].exists, "Queued prompt edit button must exist")
        XCTAssertTrue(app.buttons["deleteQueuedPromptButton"].exists, "Queued prompt delete button must exist")
        XCTAssertTrue(app.buttons["stopGenerationButton"].exists, "Running state Stop square button must exist")
        XCTAssertTrue(app.buttons["floatingTodoPillButton"].exists, "Floating active Todo pill must exist")
        saveScreenshot(name: "02-Running-Task-Prompt-Queue-Steer")

        // Tap "↑ Steer" to verify live steering execution
        steerBtn.tap()
        sleep(1)

        // Test "+" Attachment & Shortcut Hints Popover (1:1 Screenshot 3)
        let plusBtn = app.buttons["attachMenuButton"]
        XCTAssertTrue(plusBtn.exists)
        plusBtn.tap()
        XCTAssertTrue(app.staticTexts["Attachments"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Workflow"].exists)
        XCTAssertTrue(app.staticTexts["Add context"].exists)
        XCTAssertTrue(app.staticTexts["Choose capabilities"].exists)
        XCTAssertTrue(app.staticTexts["Choose skills"].exists)
        XCTAssertTrue(app.staticTexts["Type to search plugins, files, and chats"].exists)
        saveScreenshot(name: "03-Popover-Plus-Menu-1to1")

        // Tap "[/] Choose capabilities" shortcut row -> Opens "/" Slash Capabilities Popover (1:1 Screenshot 1)
        app.buttons["shortcutChooseCapabilitiesRow"].tap()
        XCTAssertTrue(app.staticTexts["/goal"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Turn on auto-mode"].exists)
        XCTAssertTrue(app.staticTexts["/workflow"].exists)
        XCTAssertTrue(app.staticTexts["/compact"].exists)
        XCTAssertTrue(app.staticTexts["/init"].exists)
        XCTAssertTrue(app.staticTexts["Plan mode"].exists)
        XCTAssertTrue(app.staticTexts["adversarial-verify"].exists)
        XCTAssertTrue(app.staticTexts["Type to search commands, skills, or agents"].exists)
        saveScreenshot(name: "04-Popover-Slash-Commands-1to1")

        // Switch input to "@" -> Opens "@" Mention Context Popover with Colored Plugin Icons (1:1 Screenshot 2)
        let composer = app.textFields["composerTextField"]
        XCTAssertTrue(composer.exists)
        composer.tap()
        composer.typeText(XCUIKeyboardKey.delete.rawValue)
        composer.typeText("@")
        XCTAssertTrue(app.staticTexts["Visualize"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Node Repl Host"].exists)
        XCTAssertTrue(app.staticTexts["Browser Use"].exists)
        XCTAssertTrue(app.staticTexts["Documents"].exists)
        XCTAssertTrue(app.staticTexts["PDF"].exists)
        XCTAssertTrue(app.staticTexts["Presentations"].exists)
        XCTAssertTrue(app.staticTexts["Spreadsheets"].exists)
        XCTAssertTrue(app.staticTexts["Type to search plugins, files, or conversations"].exists)
        saveScreenshot(name: "05-Popover-At-Mentions-1to1")

        composer.typeText(XCUIKeyboardKey.delete.rawValue)

        // Return to ZCode Remote Home
        let backHomeBtn = app.buttons["backToTaskHomeButton"]
        XCTAssertTrue(backHomeBtn.waitForExistence(timeout: 4))
        backHomeBtn.tap()

        // 3. Navigate to Automations & Back to Home
        app.buttons["openAutomationsRowButton"].tap()
        let backFromAuto = app.buttons["backFromAutomationsButton"]
        XCTAssertTrue(backFromAuto.waitForExistence(timeout: 4))
        saveScreenshot(name: "06-Automations-Page")
        backFromAuto.tap()

        // 4. Navigate to Plugin Marketplace & Back to Home
        let openMarketplace = app.buttons["openPluginMarketplaceRowButton"]
        XCTAssertTrue(openMarketplace.waitForExistence(timeout: 4))
        openMarketplace.tap()
        let backFromMarket = app.buttons["backFromMarketplaceButton"]
        XCTAssertTrue(backFromMarket.waitForExistence(timeout: 4))
        saveScreenshot(name: "07-Plugin-Marketplace-Page")
        backFromMarket.tap()

        // 5. Tap Main Task Row to Enter Authentic ZCode "Task chat"
        let mainTaskRow = app.buttons["sessionRow_task-rpc-refactor"]
        XCTAssertTrue(mainTaskRow.waitForExistence(timeout: 4))
        mainTaskRow.tap()

        XCTAssertTrue(app.staticTexts["Task chat"].waitForExistence(timeout: 4))
        let changesPill = app.buttons["floatingChangesPill"]
        XCTAssertTrue(changesPill.waitForExistence(timeout: 4))
        let bgWorksBtn = app.buttons["composerBackgroundWorksButton"]
        XCTAssertTrue(bgWorksBtn.exists, "Composer [∿ 3] background works pill must exist")
        saveScreenshot(name: "08-Task-Chat-ZCode-Remote")

        // 5b. Tap Composer "[∿ 3]" Badge -> Opens 1:1 Unified Floating Task/Status Panel ("Thanh task")
        bgWorksBtn.tap()
        XCTAssertTrue(app.staticTexts["Git tools"].waitForExistence(timeout: 4), "Git tools section must exist in StatusPanel")
        XCTAssertTrue(app.staticTexts["Commit or push"].exists, "Commit or push row must exist")
        XCTAssertTrue(app.staticTexts["Progress"].exists, "Progress section must exist")
        XCTAssertTrue(app.staticTexts["3/5"].exists, "Progress 3/5 counter must exist")
        saveScreenshot(name: "08b-Unified-Task-Status-Panel-Top")

        // Scroll inside Unified Task Status Panel to inspect Goal + Agents ("3 running")
        let statusPanel = app.otherElements["unifiedTaskStatusPanel"]
        statusPanel.swipeUp()
        XCTAssertTrue(app.staticTexts["Goal"].waitForExistence(timeout: 3), "Goal section must exist")
        XCTAssertTrue(app.staticTexts["Agents"].exists, "Agents section must exist")
        XCTAssertTrue(app.staticTexts["3 running"].exists, "Agents 3 running label must exist")
        saveScreenshot(name: "08c-Unified-Task-Status-Panel-Goal-Agents")

        // 5c. Tap SubAgent Row -> Opens 1:1 Slide-Over SubAgent Multi-Tab Transcript View
        let subagentRow = app.buttons["statusSubagentRow_sub-rpc-framing"]
        XCTAssertTrue(subagentRow.exists)
        subagentRow.tap()

        XCTAssertTrue(app.buttons["subagentTab_sub-rpc-framing"].waitForExistence(timeout: 4), "Active SubAgent tab pill must exist")
        XCTAssertTrue(app.buttons["newSubagentTabButton"].exists, "SubAgent + tab button must exist")
        XCTAssertTrue(app.buttons["subagentArtifactPreviewButton"].exists, "Embedded SubAgent image preview must exist")
        XCTAssertTrue(app.buttons["copySubagentTranscriptButton"].exists, "SubAgent Copy button must exist")
        saveScreenshot(name: "08d-SubAgent-SlideOver-Transcript-1to1")

        // Dismiss Slide-Over SubAgent Drawer via switcher menu
        app.buttons["subagentSwitcherMenuButton"].tap()
        let closeSubagentBtn = app.buttons["Close SubAgent View"]
        XCTAssertTrue(closeSubagentBtn.waitForExistence(timeout: 3))
        closeSubagentBtn.tap()
        XCTAssertTrue(changesPill.waitForExistence(timeout: 4), "Floating Changes pill must reappear after closing SubAgent drawer")

        // 6. Tap Floating "Changes +add -del" Pill -> Opens Slide-Over Right Side-Pane on Git Diff
        changesPill.tap()
        let closeInspector = app.buttons["closeInspectorButton"]
        XCTAssertTrue(closeInspector.waitForExistence(timeout: 5))
        saveScreenshot(name: "09-SidePane-Git-Changes-Overlay")

        // 7. Expand Side-Pane to Full Width & Toggle Split Diff
        app.buttons["expandInspectorButton"].tap()
        let splitToggle = app.buttons["toggleSplitDiffButton"]
        if splitToggle.waitForExistence(timeout: 3) {
            splitToggle.tap()
        }
        saveScreenshot(name: "10-SidePane-Expanded-Split-Diff")

        // 8. Side-Pane: Files & Syntax Code Viewer + File Tree
        app.buttons["inspectorTab_files"].tap()
        saveScreenshot(name: "11-SidePane-Syntax-Code-Viewer")

        let toggleTree = app.buttons["toggleFileTreeButton"]
        if toggleTree.waitForExistence(timeout: 3) {
            toggleTree.tap()
            saveScreenshot(name: "12-SidePane-File-Tree")
            toggleTree.tap()
        }

        // 9. Side-Pane: Image / PDFKit / CSV Document Viewer
        app.buttons["inspectorTab_preview"].tap()
        let archChip = app.buttons["previewAssetChip_file-arch-png"]
        if archChip.waitForExistence(timeout: 3) {
            archChip.tap()
        }
        saveScreenshot(name: "13-SidePane-Image-Viewer")

        let pdfChip = app.buttons["previewAssetChip_file-spec-pdf"]
        XCTAssertTrue(pdfChip.waitForExistence(timeout: 3))
        pdfChip.tap()
        saveScreenshot(name: "14-SidePane-PDFKit-Viewer")

        let csvChip = app.buttons["previewAssetChip_file-benchmarks-csv"]
        XCTAssertTrue(csvChip.waitForExistence(timeout: 3))
        csvChip.tap()
        saveScreenshot(name: "15-SidePane-CSV-Table")

        // 10. Side-Pane: Integrated Terminal & Multi-Agent Workflow Graph
        app.buttons["inspectorTab_terminal"].tap()
        let termField = app.textFields["terminalInputField"]
        XCTAssertTrue(termField.waitForExistence(timeout: 3))
        termField.tap()
        termField.typeText("git status")
        app.buttons["terminalRunButton"].tap()
        saveScreenshot(name: "16-SidePane-Native-Terminal")

        app.buttons["inspectorTab_workflows"].tap()
        saveScreenshot(name: "17-SidePane-Workflow-DAG")

        // Close Side-Pane and Navigate Back "←" to ZCode Remote Home
        closeInspector.tap()
        XCTAssertTrue(backHomeBtn.waitForExistence(timeout: 4))
        backHomeBtn.tap()

        // 11. Select Session Awaiting Permission Gate & Approve
        let approvalRow = app.buttons["sessionRow_task-security-audit"]
        XCTAssertTrue(approvalRow.waitForExistence(timeout: 4))
        approvalRow.tap()

        let allowOnce = app.buttons["allowOncePermissionButton"]
        XCTAssertTrue(allowOnce.waitForExistence(timeout: 4))
        saveScreenshot(name: "18-Interactive-Permission-Approval")
        allowOnce.tap()

        // 12. Return to Home -> Open Settings (19 Categories)
        app.buttons["backToTaskHomeButton"].tap()
        let settingsBtn = app.buttons["sidebarSettingsButton"]
        XCTAssertTrue(settingsBtn.waitForExistence(timeout: 4))
        settingsBtn.tap()

        let appearanceNav = app.buttons["settingsNav_appearance"]
        XCTAssertTrue(appearanceNav.waitForExistence(timeout: 4))
        saveScreenshot(name: "19-Enterprise-Settings-19-Categories")

        appearanceNav.tap()
        XCTAssertTrue(app.buttons["themeOption_dark"].waitForExistence(timeout: 4))
        saveScreenshot(name: "20-Settings-Appearance-Editor")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["closeSettingsButton"].tap()
    }

    @MainActor
    func test03SettingsModelProviderAndSubagentStudio1to1UX() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-seed-workspace"]
        app.launch()

        let settingsBtn = app.buttons["sidebarSettingsButton"]
        XCTAssertTrue(settingsBtn.waitForExistence(timeout: 8))
        settingsBtn.tap()

        // 1. Settings Root (3 Official ZCode Groups / 16 Sections)
        let modelNav = app.buttons["settingsNav_modelProvider"]
        XCTAssertTrue(modelNav.waitForExistence(timeout: 4))
        saveScreenshot(name: "21-Settings-Root-ZCode-1to1")

        // 2. Open Model Settings -> Verify Built-in Z.ai Plans + Custom Providers + Add Provider Sheet
        modelNav.tap()
        let addProviderBtn = app.buttons["addProviderButton"]
        XCTAssertTrue(addProviderBtn.waitForExistence(timeout: 4))
        saveScreenshot(name: "22-Settings-Model-Providers-List")

        addProviderBtn.tap()
        XCTAssertTrue(app.buttons["createCustomProviderButton"].waitForExistence(timeout: 4))
        saveScreenshot(name: "23-Settings-Add-Provider-17-Templates")
        app.navigationBars.buttons["Cancel"].tap()

        // Open Anthropic Provider Studio -> Inspect API Key + Models + Add Model Sheet
        let anthropicRow = app.buttons["providerRow_anthropic"]
        if anthropicRow.waitForExistence(timeout: 4) {
            anthropicRow.tap()
            let addModelBtn = app.buttons["addModelButton"]
            XCTAssertTrue(addModelBtn.waitForExistence(timeout: 4))
            saveScreenshot(name: "24a-Settings-Provider-Detail-Top")

            app.swipeUp()
            saveScreenshot(name: "24b-Settings-Provider-Detail-Models-Connectivity")

            addModelBtn.tap()
            XCTAssertTrue(app.buttons["saveModelConfigButton"].waitForExistence(timeout: 4))
            saveScreenshot(name: "25-Settings-Model-Config-Capabilities-Editor")
            app.navigationBars.buttons["Cancel"].tap()

            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        // Back to Settings Root (on iPhone stack)
        let subagentsNav = app.buttons["settingsNav_subagents"]
        if !subagentsNav.exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        // 3. Open Subagents Studio -> Custom, Built-in & Plugin Agents + Create Subagent Sheet
        XCTAssertTrue(subagentsNav.waitForExistence(timeout: 4))
        subagentsNav.tap()
        let createSubagentBtn = app.buttons["createSubagentButton"]
        XCTAssertTrue(createSubagentBtn.waitForExistence(timeout: 4))
        saveScreenshot(name: "26-Settings-Subagents-Studio-List")

        createSubagentBtn.tap()
        let nameField = app.textFields["subagentNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 4))
        saveScreenshot(name: "27-Settings-Create-Subagent-Editor-Top")

        app.swipeUp()
        let allowAllToggle = app.switches.matching(NSPredicate(format: "label CONTAINS 'Allow All Tools'")).firstMatch
        if allowAllToggle.exists {
            allowAllToggle.tap()
        }
        saveScreenshot(name: "28-Settings-Create-Subagent-Tools-Grid")
        app.navigationBars.buttons["Cancel"].tap()
    }

    private func saveScreenshot(name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
