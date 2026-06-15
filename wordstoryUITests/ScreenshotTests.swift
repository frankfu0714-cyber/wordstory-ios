import XCTest

/// Captures the six App Store marketing screenshots required for submission.
///
/// Runs the app with `--seedDemo` so words + saved stories + a pre-generated
/// Story-tab payload are all pre-populated (see `SeedDemo` in the app target).
/// Each screenshot is written directly to the outputs folder via the runner
/// process — `XCUITest` runs on the host, so host filesystem writes work
/// without any extra plumbing.
///
/// Each method launches the app fresh so a failure in one screenshot doesn't
/// cascade. They run alphabetically, which matches the desired numbering.
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

    // MARK: - 6 screenshots

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
            // Fallback: tap well outside the static-text frame so we land in
            // the row body rather than the speaker overlay.
            vandalizeText.coordinate(withNormalizedOffset: CGVector(dx: -1.0, dy: 0.5)).tap()
        }
        // Flip animation is .easeInOut(0.55); auto-hide doesn't fire until 5s.
        usleep(1_500_000)
        save("03-flashcard-back")
    }

    func test04_storyEnglish() {
        let app = launchSeeded()
        let storyTab = app.tabBars.buttons.element(boundBy: 1)
        XCTAssertTrue(storyTab.waitForExistence(timeout: 3))
        storyTab.tap()
        // The seeded story hydrates on appear; the toggle button confirms
        // the storyOutput rendered.
        let showChinese = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Show Chinese' OR label CONTAINS '顯示中文'")
        ).firstMatch
        XCTAssertTrue(showChinese.waitForExistence(timeout: 5),
                      "seeded story didn't render")
        sleep(1)
        save("04-story-english")
    }

    func test05_storyWithChinese() {
        let app = launchSeeded()
        let storyTab = app.tabBars.buttons.element(boundBy: 1)
        XCTAssertTrue(storyTab.waitForExistence(timeout: 3))
        storyTab.tap()
        let showChinese = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Show Chinese' OR label CONTAINS '顯示中文'")
        ).firstMatch
        XCTAssertTrue(showChinese.waitForExistence(timeout: 5))
        showChinese.tap()
        sleep(1)
        save("05-story-with-chinese")
    }

    func test06_savedStories() {
        let app = launchSeeded()
        let savedTab = app.tabBars.buttons.element(boundBy: 2)
        XCTAssertTrue(savedTab.waitForExistence(timeout: 3))
        savedTab.tap()
        sleep(2)
        save("06-saved-stories")
    }
}
