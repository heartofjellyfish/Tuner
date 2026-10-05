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
    func testFixedMainLayout() {
        launch()
        XCTAssertEqual(app.scrollViews.count, 0)
        let before = app.buttons["instrumentMenu"].frame
        app.swipeUp()
        XCTAssertEqual(app.buttons["instrumentMenu"].frame.minY, before.minY, accuracy: 1)
        XCTAssertFalse(app.staticTexts["Tune up"].exists)
        screenshot("fixed-arc-six-strings")
        app.buttons["tuningMenu"].tap()
        app.swipeUp()
        app.buttons["8-string"].tap()
        for number in 1...8 {
            let button = app.buttons["string-\(number)"]
            XCTAssertTrue(button.isHittable)
            XCTAssertLessThanOrEqual(button.frame.maxY, app.frame.maxY)
            button.tap()
            XCTAssertEqual(button.value as? String, "Locked")
        }
        screenshot("fixed-arc-eight-strings")
    }
    func testNoiseFloorStaysQuiet() {
        launch(["--noise-floor"])
        XCTAssertEqual(app.descendants(matching: .any)["inputStatus"].value as? String, "0")
        XCTAssertEqual(app.otherElements["pitchDisplay"].label, "Guitar tuner")
        screenshot("noise-floor-flat")
    }
    func testWeakInputActivityWithoutPitch() {
        launch(["--weak-input"])
        let meter = app.descendants(matching: .any)["inputStatus"]
        expectation(for: NSPredicate { _, _ in Int(meter.value as? String ?? "0") ?? 0 > 0 }, evaluatedWith: meter)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.otherElements["pitchDisplay"].label, "Guitar tuner")
        screenshot("weak-input-no-pitch")
        expectation(for: NSPredicate(format: "value == %@", "0"), evaluatedWith: meter)
        waitForExpectations(timeout: 12)
        XCTAssertEqual(app.otherElements["pitchDisplay"].label, "Guitar tuner")
        screenshot("input-silent")
    }
    func testThemeSelectionAndPersistence() {
        launch()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.buttons["theme-blue"].waitForExistence(timeout: 5))
        for theme in ["chalk", "graphite", "blue"] {
            app.buttons["theme-\(theme)"].tap()
            XCTAssertEqual(app.buttons["theme-\(theme)"].value as? String, "Selected")
            screenshot("theme-\(theme)-settings")
            app.buttons["Done"].tap()
            XCTAssertFalse(app.buttons["reference"].exists)
            screenshot("theme-\(theme)-guitar")
            app.buttons["instrumentMenu"].tap()
            XCTAssertTrue(app.buttons["Ukulele"].waitForExistence(timeout: 3))
            screenshot("theme-\(theme)-instruments")
            app.buttons["Guitar"].tap()
            app.buttons["settings"].tap()
        }
        app.buttons["theme-chalk"].tap()
        app.terminate()
        app.launchArguments = ["--preview"]
        app.launch()
        app.buttons["settings"].tap()
        XCTAssertEqual(app.buttons["theme-chalk"].value as? String, "Selected")
        app.buttons["theme-blue"].tap()
        app.buttons["Done"].tap()
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
    func testEveryInstrumentArtworkAndTargets() {
        launch()
        let instruments: [(String, [String])] = [
            ("Guitar", ["E2", "A2", "D3", "G3", "B3", "E4"]),
            ("Ukulele", ["G4", "C4", "E4", "A4"]),
            ("Bass", ["E1", "A1", "D2", "G2"]),
            ("Violin", ["G3", "D4", "A4", "E5"]),
            ("Viola", ["C3", "G3", "D4", "A4"]),
            ("Cello", ["C2", "G2", "D3", "A3"]),
            ("Banjo", ["G4", "D3", "G3", "B3", "D4"]),
            ("Mandolin", ["G3", "D4", "A4", "E5"])
        ]
        for (name, notes) in instruments {
            app.buttons["instrumentMenu"].tap()
            let row = app.buttons["instrument-\(name)"]
            for _ in 0..<4 where !row.isHittable { app.scrollViews.firstMatch.swipeUp() }
            XCTAssertTrue(row.isHittable, name)
            row.tap()
            XCTAssertTrue(app.buttons["tuningMenu"].waitForExistence(timeout: 3))
            XCTAssertEqual(app.scrollViews.count, 0)
            for (index, note) in notes.enumerated() {
                let string = app.buttons["string-\(notes.count - index)"]
                XCTAssertTrue(string.label.contains(note), "\(name): \(note)")
                XCTAssertTrue(string.isHittable, "\(name): \(note)")
                XCTAssertGreaterThanOrEqual(string.frame.height, 44)
                XCTAssertLessThanOrEqual(string.frame.maxY, app.frame.maxY)
                string.tap()
                XCTAssertTrue((string.value as? String)?.contains("Locked") == true)
                app.buttons["autoString"].tap()
            }
            screenshot("headstock-\(name)")
        }
        app.buttons["instrumentMenu"].tap()
        screenshot("instrument-silhouette-menu-bottom")
        app.scrollViews.firstMatch.swipeDown()
        screenshot("instrument-silhouette-menu-top")
    }
    func testExtendedBassArtworkAndTargets() {
        launch()
        app.buttons["instrumentMenu"].tap()
        app.buttons["instrument-Bass"].tap()
        for count in [5, 6] {
            app.buttons["tuningMenu"].tap()
            app.buttons["\(count)-string"].tap()
            for number in 1...count {
                let string = app.buttons["string-\(number)"]
                XCTAssertTrue(string.isHittable)
                string.tap()
                XCTAssertTrue((string.value as? String)?.contains("Locked") == true)
                app.buttons["autoString"].tap()
            }
            screenshot("headstock-bass-\(count)-strings")
        }
    }
    func testChromaticRingStatesAndLayout() {
        for (offset, expected) in [("-25", "A4"), ("-8", "A4"), ("0", "A4"), ("25", "A4"), ("75", "A♯4")] {
            launch(["--chromatic", "--cents", offset])
            let display = app.otherElements["pitchDisplay"]
            XCTAssertEqual(display.label, expected)
            XCTAssertEqual(app.scrollViews.count, 0)
            XCTAssertLessThan(display.frame.maxY, app.frame.maxY)
            XCTAssertGreaterThan(display.frame.minY, app.descendants(matching: .any)["inputStatus"].frame.maxY)
            XCTAssertFalse(app.buttons["holdPitch"].exists)
            screenshot("chromatic-ring-\(offset)")
            app.terminate()
        }
        launch(["--chromatic", "--midi", "68", "--cents", "49"])
        XCTAssertEqual(app.otherElements["pitchDisplay"].label, "G♯4")
        screenshot("chromatic-before-wrap")
        app.terminate()
        launch(["--chromatic", "--midi", "68", "--cents", "51"])
        XCTAssertEqual(app.otherElements["pitchDisplay"].label, "A4")
        screenshot("chromatic-after-wrap")
        app.terminate()
        launch(["--chromatic", "--silent"])
        XCTAssertEqual(app.otherElements["pitchDisplay"].value as? String, "Play a note")
        screenshot("chromatic-ring-silent")
    }
    func testChromaticVoiceResponse() {
        launch(["--chromatic", "--voice-test"])
        let display = app.otherElements["pitchDisplay"]
        expectation(for: NSPredicate(format: "label == %@ AND value CONTAINS %@", "A4", "IN TUNE"), evaluatedWith: display)
        waitForExpectations(timeout: 5)
        for _ in 0..<5 {
            Thread.sleep(forTimeInterval: 0.3)
            XCTAssertTrue((display.value as? String)?.contains("IN TUNE") == true)
        }
        screenshot("voice-wavering-stable")
        app.buttons["settings"].tap()
        let response = app.buttons["pitchResponse"]
        XCTAssertTrue((response.value as? String)?.contains("Voice") == true)
        response.tap()
        XCTAssertTrue((response.value as? String)?.contains("Fine") == true)
        app.terminate()
        app.launchArguments = ["--preview", "--chromatic"]
        app.launch()
        app.buttons["settings"].tap()
        XCTAssertTrue((app.buttons["pitchResponse"].value as? String)?.contains("Fine") == true)
        app.buttons["pitchResponse"].tap()
    }
    func testChromaticInstrumentDropdown() {
        launch(["--chromatic"])
        XCTAssertTrue(app.buttons["instrumentMenu"].isHittable)
        app.buttons["instrumentMenu"].tap()
        app.buttons["Guitar"].tap()
        XCTAssertEqual(app.buttons["instrumentMenu"].label, "Instrument, Guitar")
        XCTAssertTrue(app.buttons["string-6"].exists)
        app.buttons["instrumentMenu"].tap()
        app.buttons["Chromatic"].tap()
        XCTAssertEqual(app.buttons["instrumentMenu"].label, "Instrument, Chromatic")
        screenshot("chromatic-dropdown")
    }
    func testChromaticHoldAndCalibration() {
        launch(["--chromatic"])
        XCTAssertFalse(app.buttons["holdPitch"].exists)
        app.buttons["settings"].tap()
        XCTAssertTrue(app.buttons["holdPitch"].exists)
        app.buttons["holdPitch"].tap()
        XCTAssertEqual(app.buttons["holdPitch"].label, "Release held pitch")
        screenshot("chromatic-held")
        app.buttons["holdPitch"].tap()
        app.buttons["reference"].tap()
        app.buttons["reference-442"].tap()
        app.buttons["close-Concert A"].tap()
        XCTAssertTrue(app.buttons["reference"].label.contains("442"))
        XCTAssertTrue(app.buttons["referenceTone"].waitForExistence(timeout: 3))
        screenshot("settings")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["instrumentMenu"].exists)
    }
    func testSilenceAndPermissionRecoveryUI() {
        launch(["--silent"])
        XCTAssertEqual(app.otherElements["pitchDisplay"].label, "Guitar tuner")
        XCTAssertTrue(app.otherElements["pitchDisplay"].value as? String == "Pluck a string")
        app.buttons["string-6"].tap()
        XCTAssertEqual(app.buttons["string-6"].value as? String, "Locked")
        app.buttons["autoString"].tap()
        XCTAssertNotEqual(app.buttons["string-6"].value as? String, "Detected")
        XCTAssertNotEqual(app.buttons["string-6"].value as? String, "Locked")
        screenshot("silence")
        app.terminate()
        launch(["--denied"])
        XCTAssertTrue(app.staticTexts["Microphone"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Settings"].exists)
        app.buttons["Dismiss"].tap()
        XCTAssertEqual(app.descendants(matching: .any)["inputStatus"].label, "PREVIEW")
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
        let released = NSPredicate(format: "value == %@", "Pluck a string")
        expectation(for: released, evaluatedWith: display)
        waitForExpectations(timeout: 10) // includes the new three-second last-reading hold
    }

    func testStringProgressCompletionDriftAndReset() {
        launch(["--progress-test"])
        for number in stride(from: 6, through: 1, by: -1) {
            let string = app.buttons["string-\(number)"]
            expectation(for: NSPredicate(format: "value == %@", "Tuned"), evaluatedWith: string)
            waitForExpectations(timeout: 5)
        }
        XCTAssertTrue((app.otherElements["pitchDisplay"].value as? String)?.contains("ALL STRINGS TUNED") == true)
        screenshot("all-strings-tuned")
        let lowE = app.buttons["string-6"]
        expectation(for: NSPredicate(format: "value != %@", "Tuned"), evaluatedWith: lowE)
        waitForExpectations(timeout: 7)
        XCTAssertEqual(app.buttons["string-5"].value as? String, "Tuned")
        screenshot("string-drift-clears-mark")
        expectation(for: NSPredicate(format: "value == %@", "Tuned"), evaluatedWith: lowE)
        waitForExpectations(timeout: 6)
        app.terminate()
        launch(["--completed"])
        XCTAssertEqual(app.buttons["string-6"].value as? String, "Tuned")
        app.buttons["settings"].tap()
        let sound = app.buttons["successSound"]
        tapVisible(sound)
        XCTAssertNotEqual(sound.value as? String, "Selected")
        tapVisible(app.buttons["resetProgress"])
        app.buttons["Done"].tap()
        XCTAssertNotEqual(lowE.value as? String, "Tuned")
        app.terminate()
        app.launchArguments = ["--preview"]
        app.launch()
        app.buttons["settings"].tap()
        XCTAssertNotEqual(app.buttons["successSound"].value as? String, "Selected")
        app.buttons["successSound"].tap()
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
        expectation(for: NSPredicate(format: "value == %@", "Pluck a string"), evaluatedWith: display)
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


    @discardableResult private func tapVisible(_ element: XCUIElement) -> String {
        for _ in 0..<16 {
            let frame = element.exists ? element.frame : .zero
            if element.exists && element.isHittable && frame.midY > 160 && frame.midY < app.frame.maxY - 20 {
                let title = element.label
                element.tap(); return title
            }
            // Native swipes cancel button presses correctly while scrolling.
            let down = element.exists && frame.midY < 160
            if down { app.swipeDown(velocity: .slow) }
            else { app.swipeUp(velocity: .slow) }
        }
        XCTFail("Could not reach \(element)")
        return ""
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

    func testEveryPresetCanBeSelected() {
        launch()
        let catalogue: [(String, [String])] = [
            ("Guitar", ["standard", "drop-d", "half-down", "dadgad", "open-g", "open-d", "whole-down", "drop-c", "open-e", "open-c", "double-drop-d", "seven", "eight"]),
            ("Ukulele", ["high-g", "low-g", "baritone", "d-tuning", "low-a", "slack-key", "half-down"]),
            ("Bass", ["standard", "five", "six", "drop-d", "half-down", "d-standard", "drop-c", "drop-a"]),
            ("Violin", ["standard", "cross-a", "cross-g", "calico", "five"]),
            ("Viola", ["standard", "half-down", "whole-down"]),
            ("Cello", ["standard", "bach", "half-down", "whole-down"]),
            ("Banjo", ["open-g", "double-c", "sawmill", "open-d", "standard-c", "tenor", "irish"]),
            ("Mandolin", ["standard", "cross-g", "cross-a", "octave", "mandola"])
        ]
        var checked = 0
        for (instrument, presets) in catalogue {
            app.buttons["instrumentMenu"].tap()
            tapVisible(app.buttons["instrument-" + instrument])
            for preset in presets {
                app.buttons["tuningMenu"].tap()
                let row = app.buttons["tuning-" + preset]
                let chosenTitle = tapVisible(row)
                expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["close-Tuning"])
                waitForExpectations(timeout: 3)
                XCTAssertEqual(app.buttons["tuningMenu"].label, "Tuning, " + chosenTitle)
                XCTAssertTrue(app.buttons["string-1"].exists)
                app.buttons["string-1"].tap()
                XCTAssertEqual(app.buttons["string-1"].value as? String, "Locked")
                app.buttons["autoString"].tap()
                XCTAssertNotEqual(app.buttons["string-1"].value as? String, "Locked")
                checked += 1
            }
            screenshot("audit-" + instrument)
        }
        XCTAssertEqual(checked, 52)
        // Each instrument retains its own last selection.
        app.buttons["instrumentMenu"].tap()
        tapVisible(app.buttons["instrument-Guitar"])
        XCTAssertTrue(app.buttons["string-8"].exists)
        app.terminate()
        app.launchArguments = ["--preview"]
        app.launch()
        XCTAssertTrue(app.buttons["string-8"].waitForExistence(timeout: 5))
    }

    func testCalibrationBoundsAndPersistence() {
        launch()
        XCTAssertFalse(app.buttons["reference"].exists)
        XCTAssertFalse(app.buttons["autoString"].exists)
        app.buttons["settings"].tap()
        app.buttons["reference"].tap()
        let slider = app.sliders["Concert A frequency"]
        slider.adjust(toNormalizedSliderPosition: 0)
        XCTAssertFalse(app.buttons["Lower reference"].isEnabled)
        app.buttons["close-Concert A"].tap()
        XCTAssertTrue(app.buttons["reference"].label.contains("420"))
        app.buttons["reference"].tap()
        slider.adjust(toNormalizedSliderPosition: 1)
        XCTAssertFalse(app.buttons["Raise reference"].isEnabled)
        app.buttons["close-Concert A"].tap()
        XCTAssertTrue(app.buttons["reference"].label.contains("460"))
        app.buttons["reference"].tap()
        app.buttons["reference-432"].tap()
        app.buttons["Raise reference"].tap()
        app.buttons["Lower reference"].tap()
        app.buttons["close-Concert A"].tap()
        XCTAssertTrue(app.buttons["reference"].label.contains("432"))
        app.terminate(); app.launchArguments = ["--preview"]; app.launch()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.buttons["reference"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reference"].label.contains("432"))
    }

    func testCustomLimitsAndCancel() {
        launch()
        app.buttons["tuningMenu"].tap(); app.buttons["newCustom"].tap()
        app.buttons["Remove string"].tap(); app.buttons["Remove string"].tap()
        XCTAssertFalse(app.buttons["Remove string"].isEnabled)
        for _ in 0..<4 { app.buttons["Add string"].tap() }
        XCTAssertFalse(app.buttons["Add string"].isEnabled)
        app.buttons["edit-string-8"].tap()
        app.buttons["Lower octave"].tap(); app.buttons["Lower octave"].tap()
        XCTAssertFalse(app.buttons["Lower octave"].isEnabled)
        for _ in 0..<5 { app.buttons["Raise octave"].tap() }
        XCTAssertFalse(app.buttons["Raise octave"].isEnabled)
        XCTAssertFalse(app.buttons["pitch-class-6"].isEnabled)
        app.buttons["pitch-class-5"].tap()
        app.buttons["close-Custom tuning"].tap()
        app.buttons["close-Tuning"].tap()
        XCTAssertTrue(app.buttons["tuningMenu"].label.contains("Standard"))
        XCTAssertFalse(app.buttons["string-8"].exists)
    }

    func testToneRespectsPausedMicrophone() {
        app.launchArguments = ["--reset"]; app.launch()
        let status = app.descendants(matching: .any)["inputStatus"]
        expectation(for: NSPredicate(format: "label == %@", "LISTENING"), evaluatedWith: status)
        waitForExpectations(timeout: 10)
        app.buttons["settings"].tap()
        app.buttons["microphoneToggle"].tap()
        app.buttons["referenceTone"].tap()
        XCTAssertEqual(app.buttons["referenceTone"].label, "Stop reference tone")
        app.buttons["referenceTone"].tap()
        XCTAssertEqual(app.buttons["microphoneToggle"].label, "Resume microphone")
        app.buttons["Done"].tap()
        XCTAssertEqual(status.label, "PAUSED")
        XCTAssertEqual(status.value as? String, "0")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertEqual(status.label, "PAUSED")
        XCTAssertEqual(status.value as? String, "0")
        app.buttons["settings"].tap(); app.buttons["microphoneToggle"].tap()
        expectation(for: NSPredicate(format: "label == %@", "Pause microphone"), evaluatedWith: app.buttons["microphoneToggle"])
        waitForExpectations(timeout: 10)
        app.buttons["referenceTone"].tap(); app.buttons["referenceTone"].tap()
        expectation(for: NSPredicate(format: "label == %@", "Pause microphone"), evaluatedWith: app.buttons["microphoneToggle"])
        waitForExpectations(timeout: 10)
    }

    func testProximityPresentationStates() {
        for (cents, name) in [("-40", "far-orange"), ("-12", "near-gold"), ("0", "center-green"), ("+12", "sharp-gold")] {
            launch(["--cents", cents])
            screenshot(name)
            XCTAssertEqual(app.otherElements["pitchDisplay"].label, "A2")
            XCTAssertTrue((app.otherElements["pitchDisplay"].value as? String)?.contains(cents == "0" ? "IN TUNE" : cents.hasPrefix("+") ? "SHARP" : "FLAT") == true)
            app.terminate()
        }
    }

    func testSystemMicrophoneDenial() {
        app.resetAuthorizationStatus(for: .microphone)
        app.launchArguments = ["--reset"]; app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deny = springboard.alerts.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Allow")).firstMatch
        // The first button is Don't Allow; explicitly verify its meaning.
        XCTAssertTrue(deny.waitForExistence(timeout: 8))
        XCTAssertTrue(deny.label.lowercased().contains("don"))
        deny.tap()
        XCTAssertTrue(app.buttons["Open Settings"].waitForExistence(timeout: 5))
        screenshot("system-microphone-denied")
        app.buttons["Dismiss"].tap()
        XCTAssertEqual(app.descendants(matching: .any)["inputStatus"].label, "MICROPHONE OFF")
        app.terminate()
        app.resetAuthorizationStatus(for: .microphone)
        app.launch()
        let allow = springboard.alerts.buttons["Allow"]
        XCTAssertTrue(allow.waitForExistence(timeout: 8)); allow.tap()
        expectation(for: NSPredicate(format: "label == %@", "LISTENING"), evaluatedWith: app.descendants(matching: .any)["inputStatus"])
        waitForExpectations(timeout: 10)
    }

}
