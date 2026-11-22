//
//  fairwayvector_golfpintheoryUITests.swift
//  fairwayvector-golfpintheoryUITests
//
//  Created by Joel spolen on 2026-09-28.
//

import XCTest
import UIKit

final class fairwayvector_golfpintheoryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppleLoginOptionIsVisibleBeforeAndAfterForeground() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let apple = app.buttons["account-apple-sign-in"]
        XCTAssertTrue(apple.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(apple.isHittable)
        let initial = XCTAttachment(screenshot: app.screenshot())
        initial.name = "Login with Apple option"
        initial.lifetime = .keepAlways
        add(initial)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(apple.waitForExistence(timeout: 10))
        XCTAssertTrue(apple.isHittable)
        let resumed = XCTAttachment(screenshot: app.screenshot())
        resumed.name = "Login after foreground"
        resumed.lifetime = .keepAlways
        add(resumed)
    }

    @MainActor
    private func launchAtHome(seedRound: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + (seedRound ? ["-ui-testing-seed-round"] : [])
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
        app.buttons["Cancel"].tap()
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
    func testSyntheticMapTargetInExploreAndRoundHoleTwo() throws {
        // App course, terrain and weather requests are mocked. MapKit may load
        // normal imagery for the synthetic fixture's location.
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-local-map", "-ui-testing-free",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["global-settings-button"].waitForExistence(timeout: 20), app.debugDescription)

        openHomeDestination("Explore a course", in: app)
        openSyntheticRecentCourse(in: app)
        assertHole(1, in: app)
        app.buttons["Next hole"].tap()
        assertHole(2, in: app)
        assertTargetCanBePlacedAndMoved(in: app, context: "Explore hole 2")

        app.buttons["course-round-actions-menu"].tap()
        app.buttons["Home"].tap()
        XCTAssertTrue(app.buttons["global-settings-button"].waitForExistence(timeout: 10))
        openHomeDestination("Start round", in: app)
        openSyntheticRecentCourse(in: app)
        let start = app.buttons["start-scored-round"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), app.debugDescription)
        scrollTo(start, in: app)
        start.tap()
        assertHole(1, in: app)
        app.buttons["Enter score for this hole"].tap()
        let next = app.buttons["score-next-page"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), app.debugDescription)
        next.tap()
        assertHole(2, in: app)
        assertTargetCanBePlacedAndMoved(in: app, context: "Round hole 2")
    }

    @MainActor
    func testBundledHillsActiveRoundTargetRenderingAcrossHoles() throws {
        // A fresh account, bundled 62/Men snapshot, mock course/terrain and no weather.
        // MapKit may fetch public imagery. No live course, terrain, auth or weather calls.
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-local-map", "-ui-testing-hills-active-round",
                               "-ui-testing-free", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let resume = app.buttons["home-resume-round"]
        XCTAssertTrue(resume.waitForExistence(timeout: 20), app.debugDescription)
        guard resume.exists else { return }
        resume.tap()

        for hole in 1...3 {
            assertHole(hole, in: app)
            captureAndAssertHillsTarget(in: app, hole: hole)
            if hole < 3 {
                let score = app.buttons["Enter score for this hole"]
                XCTAssertTrue(score.waitForExistence(timeout: 10), app.debugDescription)
                guard score.exists else { return }
                score.tap()
                let next = app.buttons["score-next-page"]
                XCTAssertTrue(next.waitForExistence(timeout: 10), app.debugDescription)
                guard next.exists else { return }
                next.tap()
            }
        }
    }

    @MainActor
    private func captureAndAssertHillsTarget(in app: XCUIApplication, hole: Int) {
        let marker = app.descendants(matching: .any).matching(identifier: "Target").firstMatch
        let distance = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "TARGET: ")).firstMatch
        XCTAssertFalse(marker.exists, "Hole \(hole): stale target")
        let before = app.screenshot()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.46)).tap()
        let hasDistance = distance.waitForExistence(timeout: 10)
        // Capture as soon as target state appears, even if its accessibility element is missing.
        let after = app.screenshot()
        let attachment = XCTAttachment(screenshot: after)
        attachment.name = "Hills round hole \(hole) immediately after target"
        attachment.lifetime = .keepAlways
        add(attachment)
        let exists = marker.exists
        XCTAssertTrue(exists, "Hole \(hole): no target element; screenshot retained")
        let center = CGPoint(x: app.frame.width * 0.72, y: app.frame.height * 0.46)
        if exists {
            let frame = marker.frame
            XCTAssertTrue(marker.isHittable, "Hole \(hole): target is not interactive")
            XCTAssertTrue(app.frame.contains(frame), "Hole \(hole): target frame outside screen: \(frame)")
            XCTAssertLessThan(hypot(frame.midX - app.frame.minX - center.x, frame.midY - app.frame.minY - center.y), 15,
                              "Hole \(hole): target frame not at tapped point: \(frame)")
        }
        XCTAssertTrue(hasDistance, "Hole \(hole): target distance missing")
        if hasDistance {
            XCTAssertNotNil(distance.label.rangeOfCharacter(from: .decimalDigits), "Hole \(hole): \(distance.label)")
            XCTAssertFalse(distance.label.contains("unavailable"), "Hole \(hole): \(distance.label)")
        }
        guard let oldPixels = ScreenshotPixels(before), let newPixels = ScreenshotPixels(after) else {
            XCTFail("Hole \(hole): could not decode screenshots")
            return
        }
        let ring = newPixels.changedAccentRing(from: oldPixels, center: center, screen: app.frame.size)
        let glyph = newPixels.changedAccentGlyph(from: oldPixels, center: center, screen: app.frame.size)
        let line = newPixels.longestChangedAccentRay(from: oldPixels, center: center, screen: app.frame.size)
        XCTAssertEqual(oldPixels.changedAccentRing(from: oldPixels, center: center, screen: app.frame.size), 0)
        XCTAssertEqual(oldPixels.changedAccentGlyph(from: oldPixels, center: center, screen: app.frame.size), 0)
        XCTAssertEqual(oldPixels.longestChangedAccentRay(from: oldPixels, center: center, screen: app.frame.size), 0)
        print("Hills hole \(hole): frame=\(exists ? String(describing: marker.frame) : "absent"), distance=\(hasDistance ? distance.label : "absent"), changed ring pixels=\(ring), glyph pixels=\(glyph), contiguous line samples=\(line)/24")
        XCTAssertGreaterThan(ring, 30, "Hole \(hole): target ring not visibly rendered in screenshot")
        XCTAssertGreaterThan(glyph, 15, "Hole \(hole): target arrow not visibly rendered in screenshot")
        XCTAssertGreaterThanOrEqual(line, 12, "Hole \(hole): target route line not visibly rendered in screenshot")
        guard exists, marker.isHittable, hasDistance else { return }
        let initialDistance = distance.label
        let initialFrame = marker.frame
        let markerCenter = marker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        markerCenter.press(forDuration: 0.2, thenDragTo: markerCenter.withOffset(CGVector(dx: 30, dy: -45)))
        let moved = expectation(for: NSPredicate { _, _ in
            distance.exists && distance.label != initialDistance
        }, evaluatedWith: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 10), .completed,
                       "Hole \(hole): target distance did not change after drag")
        XCTAssertTrue(marker.isHittable, "Hole \(hole): target disappeared after drag")
        XCTAssertGreaterThan(hypot(marker.frame.midX - initialFrame.midX, marker.frame.midY - initialFrame.midY), 10,
                             "Hole \(hole): target did not move on screen")
    }

    /// Samples actual screenshot pixels, not the accessibility tree. A newly drawn
    /// teal ring and a contiguous teal ray beyond its halo must both be present.
    private struct ScreenshotPixels {
        let width: Int
        let height: Int
        let pixels: [UInt8]

        init?(_ screenshot: XCUIScreenshot) {
            guard let image = screenshot.image.cgImage else { return nil }
            let width = image.width, height = image.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard success else { return nil }
            self.width = width
            self.height = height
            pixels = bytes
        }

        private func changedAccent(from old: ScreenshotPixels, x: CGFloat, y: CGFloat, screen: CGSize) -> Bool {
            let px = Int(x * CGFloat(width) / screen.width), py = Int(y * CGFloat(height) / screen.height)
            guard width == old.width, height == old.height, px >= 0, py >= 0, px < width, py < height else { return false }
            let i = (py * width + px) * 4
            let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
            let change = abs(r - Int(old.pixels[i])) + abs(g - Int(old.pixels[i + 1])) + abs(b - Int(old.pixels[i + 2]))
            return r < 70 && (60...155).contains(g) && (55...150).contains(b) && abs(g - b) < 35 && change > 40
        }

        func changedAccentRing(from old: ScreenshotPixels, center: CGPoint, screen: CGSize) -> Int {
            var count = 0
            for y in -24...24 {
                for x in -24...24 where (19 * 19...24 * 24).contains(x * x + y * y) {
                    if changedAccent(from: old, x: center.x + CGFloat(x), y: center.y + CGFloat(y), screen: screen) { count += 1 }
                }
            }
            return count
        }

        func changedAccentGlyph(from old: ScreenshotPixels, center: CGPoint, screen: CGSize) -> Int {
            var count = 0
            for y in -12...12 {
                for x in -12...12 where x * x + y * y <= 12 * 12 {
                    if changedAccent(from: old, x: center.x + CGFloat(x), y: center.y + CGFloat(y), screen: screen) { count += 1 }
                }
            }
            return count
        }

        func longestChangedAccentRay(from old: ScreenshotPixels, center: CGPoint, screen: CGSize) -> Int {
            var best = 0
            for angle in stride(from: 0, to: 360, by: 3) {
                let radians = CGFloat(angle) * .pi / 180
                var hits = 0
                for step in 0..<24 {
                    let radius = CGFloat(52 + step * 2)
                    let x = center.x + radius * cos(radians), y = center.y + radius * sin(radians)
                    let inMap = x > screen.width * 0.36 && y > screen.height * 0.20 && y < screen.height * 0.68
                    if inMap && (-2...2).contains(where: { offset in
                        changedAccent(from: old, x: x + CGFloat(offset), y: y, screen: screen)
                    }) {
                        hits += 1
                        best = max(best, hits)
                    } else { hits = 0 }
                }
            }
            return best
        }
    }

    @MainActor
    private func openSyntheticRecentCourse(in app: XCUIApplication) {
        let course = app.buttons["recent-course-button-mock-hills-v1"]
        XCTAssertTrue(course.waitForExistence(timeout: 10), app.debugDescription)
        scrollTo(course, in: app)
        course.tap()
    }

    @MainActor
    private func assertHole(_ number: Int, in app: XCUIApplication) {
        let header = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Hole \(number) ·")).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(header.isHittable)
    }

    @MainActor
    private func assertTargetCanBePlacedAndMoved(in app: XCUIApplication, context: String) {
        let marker = app.descendants(matching: .any).matching(identifier: "Target").firstMatch
        let distance = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "TARGET: ")).firstMatch
        XCTAssertFalse(marker.exists, "\(context): target should initially be absent")
        XCTAssertFalse(distance.exists, "\(context): target distance should initially be absent")

        // Away from the leading sidebar, top menu and bottom hole controls.
        let point = app.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.46))
        point.tap()
        XCTAssertTrue(marker.waitForExistence(timeout: 10), "\(context): \(app.debugDescription)")
        XCTAssertTrue(marker.isHittable, "\(context): marker must be on screen and interactive")
        XCTAssertTrue(distance.waitForExistence(timeout: 10), app.debugDescription)
        let initialDistance = distance.label
        XCTAssertFalse(initialDistance.contains("unavailable"), initialDistance)
        XCTAssertNotNil(initialDistance.rangeOfCharacter(from: .decimalDigits), initialDistance)
        let initialFrame = marker.frame
        XCTAssertTrue(app.frame.intersects(initialFrame), "\(context): marker is off screen: \(initialFrame)")
        let initialScreenshot = XCTAttachment(screenshot: app.screenshot())
        initialScreenshot.name = "\(context) after tap"
        initialScreenshot.lifetime = .keepAlways
        add(initialScreenshot)

        let markerCenter = marker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        markerCenter.press(forDuration: 0.2, thenDragTo: markerCenter.withOffset(CGVector(dx: 45, dy: -65)))
        let moved = expectation(for: NSPredicate { _, _ in
            distance.exists && distance.label != initialDistance
        }, evaluatedWith: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 10), .completed,
                       "\(context): target distance did not change after drag: \(app.debugDescription)")
        XCTAssertTrue(marker.isHittable, "\(context): target disappeared after drag")
        XCTAssertGreaterThan(hypot(marker.frame.midX - initialFrame.midX, marker.frame.midY - initialFrame.midY), 15,
                             "\(context): marker did not move on screen")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = context
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }


    @MainActor
    func testFreeVersionLocksTrajectoryButKeepsStartRound() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-free"]
        app.launch()
        XCTAssertTrue(app.buttons["global-settings-button"].waitForExistence(timeout: 12))
        openHomeDestination("Trajectory", in: app)
        XCTAssertTrue(app.buttons["Unlock Pro"].waitForExistence(timeout: 5))
        returnHome(in: app)
        openHomeDestination("Wedge Matrix", in: app)
        XCTAssertTrue(app.buttons["Unlock Pro"].waitForExistence(timeout: 5))
        returnHome(in: app)

        openHomeDestination("In the bag", in: app)
        let clubProfile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Club distances & launch")).firstMatch
        scrollTo(clubProfile, in: app)
        clubProfile.tap()
        let wedgeCarry = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Wedge full-swing carry")).firstMatch
        scrollTo(wedgeCarry, in: app)
        XCTAssertTrue(wedgeCarry.exists)
        app.buttons["Cancel"].tap()
        let wedgeBag = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wedge bag")).firstMatch
        scrollTo(wedgeBag, in: app)
        wedgeBag.tap()
        // Free users get the paywall instead of the wedge bag editor.
        XCTAssertFalse(app.staticTexts["Your wedge bag"].waitForExistence(timeout: 3))
        app.swipeDown(velocity: .fast)
        returnHome(in: app)

        openHomeDestination("Start round", in: app)
        XCTAssertTrue(app.staticTexts["Start a round"].waitForExistence(timeout: 5))
        returnHome(in: app)
    }

    @MainActor
    func testWedgeToolsAndWedgeBagUseHomeRoutes() {
        let app = launchAtHome()
        openHomeDestination("Wedge Matrix", in: app)
        XCTAssertTrue(app.staticTexts["Your wedge setup"].waitForExistence(timeout: 5))
        app.buttons["Matrix"].tap()
        XCTAssertTrue(app.staticTexts["Wedge Matrix"].waitForExistence(timeout: 5))
        returnHome(in: app)

        openHomeDestination("In the bag", in: app)
        let wedgeBag = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wedge bag")).firstMatch
        scrollTo(wedgeBag, in: app)
        wedgeBag.tap()
        XCTAssertTrue(app.staticTexts["Your wedge bag"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
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
        app.buttons["Find a wedge"].tap()
        XCTAssertTrue(app.staticTexts["Find your wedge"].waitForExistence(timeout: 5))
        // Slider endpoints exist even when the user has no wedges; the 20–160 yd range shows as 18–146 m.
        XCTAssertTrue(app.staticTexts["18 m"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["146 m"].exists)
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
    func testExistingStatisticsRoundUsesBack() {
        let app = launchAtHome(seedRound: true)
        openHomeDestination("Rounds & statistics", in: app)
        XCTAssertTrue(app.staticTexts["Rounds & statistics"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Your story starts here"].exists, "The seeded round should be listed")
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
