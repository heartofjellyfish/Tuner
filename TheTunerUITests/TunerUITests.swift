import XCTest

final class TunerUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }
    private func launch(_ extra: [String] = []) {
        app.launchArguments = ["--reset", "--preview"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["instrumentMenu"].waitForExistence(timeout: 10))
    }
    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testInstrumentTuningsAndLock() {
        launch()
        XCTAssertTrue(app.buttons["string-6"].exists)
        XCTAssertEqual(app.buttons["string-5"].value as? String, "Detected")
        screenshot("guitar")
        app.buttons["string-6"].tap()
        XCTAssertEqual(app.buttons["string-6"].value as? String, "Locked")
        app.buttons["autoString"].tap()
        XCTAssertEqual(app.buttons["string-5"].value as? String, "Detected")
        app.buttons["tuningMenu"].tap()
        app.buttons["Drop D"].tap()
        XCTAssertTrue(app.buttons["string-6"].label.contains("D2"))
        app.buttons["instrumentMenu"].tap()
        app.buttons["Ukulele"].tap()
        XCTAssertTrue(app.buttons["string-4"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["string-6"].exists)
        XCTAssertTrue(app.buttons["string-4"].label.contains("G4"))
        app.buttons["tuningMenu"].tap()
        app.buttons["Low G"].tap()
        XCTAssertTrue(app.buttons["string-4"].label.contains("G3"))
        app.buttons["string-3"].tap()
        XCTAssertEqual(app.buttons["string-3"].value as? String, "Locked")
        screenshot("ukulele-low-g-locked")
    }
    func testChromaticHoldAndCalibration() {
        launch(["--chromatic"])
        XCTAssertTrue(app.buttons["holdPitch"].exists)
        app.buttons["holdPitch"].tap()
        XCTAssertEqual(app.buttons["holdPitch"].label, "Release held pitch")
        screenshot("chromatic-held")
        app.buttons["holdPitch"].tap()
        app.buttons["reference"].tap()
        app.buttons["reference-442"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["reference"].label.contains("442"))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.buttons["referenceTone"].waitForExistence(timeout: 3))
        screenshot("settings")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["instrumentMenu"].exists)
    }
    func testSilenceAndPermissionRecoveryUI() {
        launch(["--silent"])
        XCTAssertTrue(app.otherElements["pitchDisplay"].value as? String == "Play a note")
        screenshot("silence")
        app.terminate()
        launch(["--denied"])
        XCTAssertTrue(app.alerts["Microphone"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.buttons["Open Settings"].exists)
        app.alerts.buttons["Dismiss"].tap()
        XCTAssertTrue(app.staticTexts["PREVIEW"].exists)
        screenshot("permission-dismissed")
    }
    func testUkuleleScreenshot() {
        launch(["--ukulele"])
        XCTAssertEqual(app.buttons["string-3"].value as? String, "Detected")
        screenshot("ukulele-in-tune")
    }
    func testPCMThroughDetectionToDisplayAndSilence() {
        launch(["--signal-test"])
        let display = app.otherElements["pitchDisplay"]
        let acquired = NSPredicate(format: "label == %@ AND value CONTAINS %@", "A2", "-8.0")
        expectation(for: acquired, evaluatedWith: display)
        waitForExpectations(timeout: 4)
        screenshot("pcm-detected-a2")
        let released = NSPredicate(format: "value == %@", "Play a note")
        expectation(for: released, evaluatedWith: display)
        waitForExpectations(timeout: 7)
    }

    func testMicrophoneLifecycle() {
        app.launchArguments = ["--reset"]
        app.launch()
        XCTAssertTrue(app.staticTexts["LISTENING"].waitForExistence(timeout: 10))
        app.buttons["settings"].tap()
        app.buttons["Pause microphone"].tap()
        XCTAssertTrue(app.buttons["Resume microphone"].waitForExistence(timeout: 3))
        app.buttons["Resume microphone"].tap()
        XCTAssertTrue(app.buttons["Pause microphone"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["LISTENING"].waitForExistence(timeout: 5))
        screenshot("microphone-running")
    }

}
