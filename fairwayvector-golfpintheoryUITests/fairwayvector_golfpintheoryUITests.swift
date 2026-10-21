//
//  fairwayvector_golfpintheoryUITests.swift
//  fairwayvector-golfpintheoryUITests
//
//  Created by Joel spolen on 2026-09-28.
//

import XCTest

final class fairwayvector_golfpintheoryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchAtHome() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["global-settings-button"].waitForExistence(timeout: 12))
        return app
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, maximumSwipes: Int = 12) {
        for _ in 0..<maximumSwipes {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "Expected a reachable element: \(element)")
    }

    @MainActor
    private func openHomeDestination(_ title: String, in app: XCUIApplication) {
        // Home rows combine their title and subtitle into a button label.
        let destination = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        scrollTo(destination, in: app)
        destination.tap()
    }

    @MainActor
    private func returnHome(in app: XCUIApplication) {
        let homeButtons = app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "return-home-button", "Home"
        ))
        XCTAssertTrue(homeButtons.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(homeButtons.count, 1, "Feature roots should expose one Home control")
        XCTAssertTrue(homeButtons.firstMatch.isHittable)
        homeButtons.firstMatch.tap()
        let settings = app.buttons["global-settings-button"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        // Home keeps its scroll position while a feature is presented.
        for _ in 0..<12 {
            if settings.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(settings.isHittable)
    }

    @MainActor
    func testTrajectoryOpensFromHomeAndReturnsHome() {
        let app = launchAtHome()
        openHomeDestination("Trajectory", in: app)
        XCTAssertTrue(app.staticTexts["Know which club to hit."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Know your flight"].exists)
        returnHome(in: app)
    }

    @MainActor
    func testHandicapOpensFromHomeAndReturnsHome() {
        let app = launchAtHome()
        openHomeDestination("Handicap", in: app)
        XCTAssertTrue(app.staticTexts["Your handicap"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Know your place on the course"].exists)
        returnHome(in: app)
    }

    @MainActor
    func testClubProfileIsInTheBagAndSettingsRemainOnHome() {
        let app = launchAtHome()
        openHomeDestination("In the bag", in: app)
        XCTAssertTrue(app.staticTexts["Build your bag"].waitForExistence(timeout: 5))
        let clubProfile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Club distances & launch")).firstMatch
        scrollTo(clubProfile, in: app)
        clubProfile.tap()
        XCTAssertTrue(app.navigationBars["Club distances & launch"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Build your bag"].waitForExistence(timeout: 5))
        returnHome(in: app)

        app.buttons["global-settings-button"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Distance units"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["global-settings-button"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCourseSelectionNavigationWithoutProviderSearch() {
        let app = launchAtHome()
        openHomeDestination("Explore a course", in: app)
        XCTAssertTrue(app.staticTexts["Explore a course"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["golf-country-picker"].exists)
        XCTAssertTrue(app.textFields["golf-club-search-field"].exists)
        // Do not search, refresh, or open a recent course: this route needs no provider or map traffic.
        returnHome(in: app)

        openHomeDestination("Start round", in: app)
        XCTAssertTrue(app.staticTexts["Start a round"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Choose your course and tee."].exists)
        returnHome(in: app)
    }

    @MainActor
    func testWedgeToolsAndWedgeBagUseHomeRoutes() {
        let app = launchAtHome()
        openHomeDestination("Wedge Matrix", in: app)
        XCTAssertTrue(app.staticTexts["Your wedge setup"].waitForExistence(timeout: 5))
        app.buttons["Matrix"].tap()
        XCTAssertTrue(app.staticTexts["Wedge matrix"].waitForExistence(timeout: 5))
        returnHome(in: app)

        openHomeDestination("In the bag", in: app)
        let wedgeBag = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wedge bag")).firstMatch
        scrollTo(wedgeBag, in: app)
        wedgeBag.tap()
        XCTAssertTrue(app.staticTexts["Your wedge bag"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        returnHome(in: app)
    }

    @MainActor
    func testDistanceUnitsAreSharedWithWedgeMatrix() {
        let app = launchAtHome()
        app.buttons["global-settings-button"].tap()
        let meters = app.buttons["Meters"]
        XCTAssertTrue(meters.waitForExistence(timeout: 5))
        let originalUnit = meters.isSelected ? "Meters" : "Yards"
        meters.tap()
        app.buttons["Done"].tap()

        openHomeDestination("Wedge Matrix", in: app)
        app.buttons["Selector"].tap()
        XCTAssertTrue(app.staticTexts["Choose a wedge"].waitForExistence(timeout: 5))
        // Slider endpoints exist even when the user has no wedges; no invented bag data is needed.
        XCTAssertTrue(app.staticTexts["20 m"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["160 m"].exists)
        returnHome(in: app)

        app.buttons["global-settings-button"].tap()
        XCTAssertTrue(app.buttons[originalUnit].waitForExistence(timeout: 5))
        app.buttons[originalUnit].tap()
        app.buttons["Done"].tap()
    }

    @MainActor
    func testStatisticsRootReturnsHome() {
        let app = launchAtHome()
        openHomeDestination("Rounds & statistics", in: app)
        XCTAssertTrue(app.staticTexts["Rounds & statistics"].waitForExistence(timeout: 5))
        returnHome(in: app)
    }

    @MainActor
    func testExistingStatisticsRoundUsesBack() throws {
        let app = launchAtHome()
        openHomeDestination("Rounds & statistics", in: app)
        XCTAssertTrue(app.staticTexts["Rounds & statistics"].waitForExistence(timeout: 5))
        // Use only genuine persisted history. A clean install cannot exercise a detail route.
        if app.staticTexts["Your story starts here"].exists {
            throw XCTSkip("No saved rounds available; no synthetic history is injected.")
        }
        let round = app.scrollViews.buttons.matching(NSPredicate(format: "label CONTAINS %@", " holes")).firstMatch
        scrollTo(round, in: app, maximumSwipes: 30)
        let roundLabel = round.label
        round.tap()

        let backButtons = app.navigationBars.buttons.matching(identifier: "Back")
        XCTAssertTrue(backButtons.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(backButtons.count, 1)
        XCTAssertFalse(app.buttons["return-home-button"].exists)
        XCTAssertFalse(app.buttons["Home"].exists)
        XCTAssertFalse(app.navigationBars.buttons["Save"].exists)
        XCTAssertFalse(app.navigationBars.buttons["Cancel"].exists)
        backButtons.firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Rounds & statistics"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[roundLabel].exists, "Back should preserve the history route")
        returnHome(in: app)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
