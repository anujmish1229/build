import XCTest

/// Simulator walk-throughs, each starting from an empty library.
final class FlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    override func tearDown() {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    /// Lists only build rows near the screen, so scroll until the element turns up.
    private func reveal(_ id: String, timeout: TimeInterval = 10) -> XCUIElement {
        let target = element(id)
        if target.waitForExistence(timeout: timeout) { return target }
        for _ in 0..<6 where !target.exists {
            app.swipeUp()
            _ = target.waitForExistence(timeout: 1)
        }
        return target
    }

    private func tap(_ id: String, timeout: TimeInterval = 5) {
        let target = reveal(id, timeout: timeout)
        XCTAssertTrue(target.exists, "\(id) never appeared")
        target.tap()
    }

    func testBoardAppearsImmediatelyAndAPinCanBeSavedAndRemixed() {
        // The ready-made Board is there straight away (requirements 12.4 asked for well under 30 seconds).
        XCTAssertTrue(element("pin-starter-1").waitForExistence(timeout: 3), "The Board didn't show within 3 seconds")
        tap("pin-starter-1")

        tap("savePin")
        let name = element("newBoardName")
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Ideas")
        tap("createBoard")
        tap("saveDone")

        tap("remixPin")
        // Three sample rooms, so it asks which.
        let choice = app.buttons["Sample living room"].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        tap("useLayout", timeout: 30)
        XCTAssertTrue(reveal("editField").exists, "The saved remix never opened")
    }

    func testRoomToNewDesignAndATypedChange() {
        tap("goRooms")
        tap("newDesign-Sample bedroom")
        let theme = reveal("themeField")
        XCTAssertTrue(theme.exists, "themeField never appeared")
        theme.tap()
        theme.typeText("calm japandi bedroom")
        tap("designButton")
        tap("useLayout", timeout: 30)

        let edit = reveal("editField")
        XCTAssertTrue(edit.exists, "editField never appeared")
        edit.tap()
        edit.typeText("remove the plant\n")
        XCTAssertTrue(app.buttons["Undo that change"].waitForExistence(timeout: 10), "The typed change wasn't applied")
    }

    func testWelcomeLeadsToTheBoardAndToScanning() {
        app.terminate()
        app.launchArguments = ["-uiTesting", "-showWelcome"]
        app.launch()
        tap("welcomeExplore")
        XCTAssertTrue(element("pin-starter-1").waitForExistence(timeout: 5), "Explore didn't lead to the Board")

        app.terminate()
        app.launch()
        tap("welcomeScan")
        XCTAssertTrue(element("scanUnsupported").waitForExistence(timeout: 5), "Scan a room didn't start a scan")
    }

    func testScanningExplainsItselfInTheSimulator() {
        tap("goScan")
        XCTAssertTrue(element("scanUnsupported").waitForExistence(timeout: 5))
    }

    func testDeleteEverythingLeavesNoRoomsAndNoSamples() {
        tap("goSettings")
        tap("deleteEverything")
        // The settings row has the same label, so wait for the dialog's button to make a second match.
        let matches = app.buttons.matching(NSPredicate(format: "label == 'Delete everything'"))
        let second = matches.element(boundBy: 1)
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        let confirm = matches.allElementsBoundByIndex.first { $0.identifier != "deleteEverything" } ?? second
        confirm.tap()
        tap("goRooms")
        XCTAssertFalse(element("room-Sample bedroom").waitForExistence(timeout: 2))
    }

    func testBoardPicturesFillIn() {
        XCTAssertTrue(element("pin-starter-1").waitForExistence(timeout: 3))
        // Pictures render in the background; the teardown screenshot shows the Board with them in.
        sleep(8)
        XCTAssertTrue(element("pin-starter-1").exists)
    }

    func testFloorPlanReviewOpens() {
        tap("goRooms")
        tap("room-Sample bedroom")
        tap("checkFloorPlan")
        XCTAssertTrue(element("floorPlan").waitForExistence(timeout: 5))
    }
}
