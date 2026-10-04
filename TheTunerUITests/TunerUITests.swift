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
        XCTAssertTrue(app.staticTexts["Microphone"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Settings"].exists)
        app.buttons["Dismiss"].tap()
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
        waitForExpectations(timeout: 10) // includes the new three-second last-reading hold
    }

    func testSuccessTailHoldAndNextString() {
        launch(["--feedback-test"])
        let display = app.otherElements["pitchDisplay"]
        expectation(for: NSPredicate(format: "label == %@ AND value CONTAINS %@", "A2", "IN TUNE"), evaluatedWith: display)
        waitForExpectations(timeout: 5)
        screenshot("settled-green")
        expectation(for: NSPredicate(format: "label == %@ AND value CONTAINS %@", "A2", "LAST READING"), evaluatedWith: display)
        waitForExpectations(timeout: 12)
        screenshot("last-reading")
        expectation(for: NSPredicate(format: "label == %@ AND NOT value CONTAINS %@", "D3", "LAST READING"), evaluatedWith: display)
        waitForExpectations(timeout: 5)
        screenshot("next-string")
        expectation(for: NSPredicate(format: "value == %@", "Play a note"), evaluatedWith: display)
        waitForExpectations(timeout: 9)
    }
    func testOptionalCentsPreference() {
        launch()
        app.buttons["settings"].tap()
        let control = app.buttons["showCents"]
        tapVisible(control)
        XCTAssertEqual(control.value as? String, "Selected")
        app.buttons["close-Settings"].tap()
        screenshot("optional-cents")
        app.terminate()
        app.launchArguments = ["--preview"]
        app.launch()
        app.buttons["settings"].tap()
        XCTAssertEqual(app.buttons["showCents"].value as? String, "Selected")
        app.buttons["showCents"].tap()
        XCTAssertNotEqual(app.buttons["showCents"].value as? String, "Selected")
    }

    func testMicrophoneLifecycle() {
        app.launchArguments = ["--reset"]
        app.launch()
        expectation(for: NSPredicate(format: "label == %@", "LISTENING"), evaluatedWith: app.descendants(matching: .any)["inputStatus"])
        waitForExpectations(timeout: 10)
        app.buttons["settings"].tap()
        let control = app.buttons["microphoneToggle"]
        expectation(for: NSPredicate(format: "label == %@ AND hittable == true", "Pause microphone"), evaluatedWith: control)
        waitForExpectations(timeout: 5)
        control.tap()
        expectation(for: NSPredicate(format: "label == %@ AND hittable == true", "Resume microphone"), evaluatedWith: control)
        waitForExpectations(timeout: 5)
        control.tap()
        expectation(for: NSPredicate(format: "label == %@", "Pause microphone"), evaluatedWith: control)
        waitForExpectations(timeout: 10)
        app.buttons["Done"].tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        expectation(for: NSPredicate(format: "label == %@", "LISTENING"), evaluatedWith: app.descendants(matching: .any)["inputStatus"])
        waitForExpectations(timeout: 5)
        screenshot("microphone-running")
    }


    private func tapVisible(_ element: XCUIElement) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { element.tap(); return }
            app.swipeUp()
        }
        XCTFail("Could not reach \(element)")
    }
    func testAllInstrumentsAndLongPresetList() {
        launch()
        for name in ["Bass", "Violin", "Viola", "Cello", "Banjo", "Mandolin", "Guitar"] {
            app.buttons["instrumentMenu"].tap()
            tapVisible(app.buttons["instrument-" + name])
            XCTAssertTrue(app.buttons["instrumentMenu"].label.contains(name))
            XCTAssertTrue(app.buttons["string-1"].exists)
        }
        app.buttons["tuningMenu"].tap()
        tapVisible(app.buttons["tuning-eight"])
        XCTAssertTrue(app.buttons["string-8"].exists)
        screenshot("guitar-eight-strings")
        app.buttons["string-8"].tap()
        XCTAssertEqual(app.buttons["string-8"].value as? String, "Locked")
    }
    func testCustomCreatePersistEditDelete() {
        launch()
        app.buttons["tuningMenu"].tap()
        screenshot("tuning-panel")
        app.buttons["newCustom"].tap()
        XCTAssertTrue(app.textFields["tuningName"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["saveTuning"].isEnabled)
        app.textFields["tuningName"].tap()
        app.textFields["tuningName"].typeText("My tuning\n")
        app.buttons["edit-string-6"].tap()
        app.buttons["pitch-class-2"].tap()
        screenshot("custom-note-editor")
        app.swipeUp()
        tapVisible(app.buttons["saveTuning"])
        app.buttons["close-Tuning"].tap()
        XCTAssertTrue(app.buttons["tuningMenu"].label.contains("My tuning"))
        XCTAssertTrue(app.buttons["string-6"].label.contains("D2"))
        app.terminate()
        app.launchArguments = ["--preview"]
        app.launch()
        XCTAssertTrue(app.buttons["tuningMenu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tuningMenu"].label.contains("My tuning"))
        app.buttons["tuningMenu"].tap()
        app.buttons["editCustom"].tap()
        XCTAssertEqual(app.textFields["tuningName"].value as? String, "My tuning")
        app.buttons["Add string"].tap()
        screenshot("custom-edit-seven")
        tapVisible(app.buttons["saveTuning"])
        app.buttons["close-Tuning"].tap()
        XCTAssertTrue(app.buttons["string-7"].exists)
        app.buttons["tuningMenu"].tap()
        app.buttons["editCustom"].tap()
        tapVisible(app.buttons["deleteTuning"])
        tapVisible(app.buttons["confirmDelete"])
        app.buttons["close-Tuning"].tap()
        XCTAssertTrue(app.buttons["tuningMenu"].label.contains("Standard"))
        XCTAssertFalse(app.buttons["string-7"].exists)
    }

}
