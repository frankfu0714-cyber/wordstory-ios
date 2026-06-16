import XCTest

/// Captures the seven App Store marketing screenshots required for
/// submission.
///
/// Runs the app with `--seedDemo` so words + two completed SavedStory rows
/// are pre-populated (see `SeedDemo` in the app target). Each screenshot is
/// written directly to the outputs folder via the runner process — XCUITest
/// runs on the host, so host filesystem writes work without any extra
/// plumbing.
///
/// Each method launches the app fresh so a failure in one screenshot
/// doesn't cascade. They run alphabetically, which matches the desired
/// numbering on disk.
@MainActor
final class ScreenshotTests: XCTestCase {

    let outputDir = "/Users/frank/Library/Application Support/Claude/local-agent-mode-sessions/d1c415a4-6d23-404d-abe0-8cfd07bc01a3/ef0c1425-9a26-4f2f-aff6-2f15044b12d0/agent/local_ditto_ef0c1425-9a26-4f2f-aff6-2f15044b12d0_g1/outputs/app-store-screenshots/6.7inch"

    override func setUpWithError() throws {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(
            atPath: outputDir, withIntermediateDirectories: true
        )
    }

    // MARK: - Helpers

    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--seedDemo"]
        app.launch()
        let firstWord = app.staticTexts["serendipity"]
        XCTAssertTrue(firstWord.waitForExistence(timeout: 10),
                      "seeded words didn't appear within timeout")
        return app
    }

    private func save(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let path = (outputDir as NSString).appendingPathComponent("\(name).png")
        do {
            try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: path))
            print("[ScreenshotTests] wrote \(path)")
        } catch {
            XCTFail("Couldn't save \(name): \(error)")
        }
    }

    /// Match either an English or zh-Hant button label on the toggle —
    /// the seed run could land in either locale depending on simulator.
    private func showChineseButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format:
                "label CONTAINS[c] 'Show Chinese' OR label CONTAINS '顯示中文'")
        ).firstMatch
    }

    private func tapSavedTab(in app: XCUIApplication) {
        let savedTab = app.tabBars.buttons.element(boundBy: 2)
        XCTAssertTrue(savedTab.waitForExistence(timeout: 3))
        savedTab.tap()
    }

    // MARK: - Screenshots

    func test01_wordsList() {
        _ = launchSeeded()
        sleep(1)
        save("01-words-list")
    }

    func test02_autocomplete() {
        let app = launchSeeded()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("se")
        sleep(2)
        save("02-autocomplete")
    }

    func test03_flashcardBack() {
        let app = launchSeeded()
        // vandalize is the newest seed → top of the list. The flip gesture
        // lives on the row's ZStack, so tap the list cell rather than the
        // inner Text element (whose tiny frame may not dispatch through to
        // the contentShape).
        let vandalizeText = app.staticTexts["vandalize"].firstMatch
        XCTAssertTrue(vandalizeText.waitForExistence(timeout: 3))
        let row = app.cells.containing(.staticText, identifier: "vandalize").firstMatch
        if row.exists {
            row.tap()
        } else {
            vandalizeText.coordinate(withNormalizedOffset: CGVector(dx: -1.0, dy: 0.5)).tap()
        }
        // Flip animation is .easeInOut(0.55); auto-hide doesn't fire until 5s.
        usleep(1_500_000)
        save("03-flashcard-back")
    }

    /// Saved tab → tap first saved row → SavedStoryDetail showing English
    /// vocabulary underlined. Auto-save replaced the inline Story-tab render,
    /// so this screenshot now lives in the detail view.
    func test04_storyEnglish() {
        let app = launchSeeded()
        tapSavedTab(in: app)
        // Tap the first saved row; the seed inserts demoStory (short_story)
        // at index 0. Use a cell predicate so the layout of the row body
        // doesn't matter.
        let firstRow = app.cells.element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5),
                      "seeded SavedStory rows didn't appear")
        firstRow.tap()
        // The detail view is ready once the Show Chinese pill renders.
        let toggle = showChineseButton(in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5),
                      "SavedStoryDetail didn't render")
        sleep(1)
        save("04-story-english")
    }

    /// Same as 04, but tap Show Chinese first so the Chinese line
    /// interleaves under each English sentence.
    func test05_storyWithChinese() {
        let app = launchSeeded()
        tapSavedTab(in: app)
        let firstRow = app.cells.element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.tap()
        let toggle = showChineseButton(in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        sleep(1)
        save("05-story-with-chinese")
    }

    func test06_savedStories() {
        let app = launchSeeded()
        tapSavedTab(in: app)
        sleep(2)
        save("06-saved-stories")
    }

    /// Type a Chinese term in the add bar → tap the autocomplete row →
    /// EnglishSynonymsSheet appears with candidate English headwords +
    /// their Chinese glosses. Demonstrates the offline-first reverse
    /// lookup + the "Words list is English-only" design choice.
    func test07_addWordSynonyms() {
        let app = launchSeeded()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("貓")
        // Autocomplete debounce is 100ms; wait through it + a beat for the
        // row to be hittable.
        usleep(400_000)
        // Tap the first autocomplete suggestion (which is "貓" itself —
        // zh prefix search orders by length, single-char first).
        let suggestion = app.buttons.matching(
            NSPredicate(format: "label == '貓'")
        ).firstMatch
        if suggestion.waitForExistence(timeout: 3) {
            suggestion.tap()
        } else {
            // Fallback: hit Enter on the field. tryAdd detects CJK and
            // opens the same sheet.
            field.typeText("\n")
        }
        // The sheet finishes loading once a candidate row (e.g. "cat") is
        // visible. reverseLookupWithGlosses is sub-millisecond so this is
        // really just waiting for the modal to slide up.
        let cat = app.staticTexts["cat"].firstMatch
        XCTAssertTrue(cat.waitForExistence(timeout: 5),
                      "synonyms sheet didn't show candidates")
        sleep(1)
        save("07-add-word-synonyms")
    }
}
