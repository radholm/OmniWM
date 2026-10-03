// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import OmniWMIPC
import XCTest

final class IPCRuleValidatorTests: XCTestCase {
    func testEmptyBundleWithoutMatchersIsInvalid() {
        let report = IPCRuleValidator.validate(IPCRuleDefinition(bundleId: ""))
        XCTAssertNotNil(report.identifierError)
        XCTAssertFalse(report.isValid)
    }

    func testEmptyBundleWithAppNameIsValid() {
        let report = IPCRuleValidator.validate(
            IPCRuleDefinition(bundleId: "", appNameSubstring: "VMD", layout: .float)
        )
        XCTAssertNil(report.identifierError)
        XCTAssertNil(report.bundleIdError)
        XCTAssertTrue(report.isValid)
    }

    func testEmptyBundleWithTitleIsValid() {
        let report = IPCRuleValidator.validate(
            IPCRuleDefinition(bundleId: "", titleSubstring: "Main", layout: .float)
        )
        XCTAssertNil(report.identifierError)
        XCTAssertTrue(report.isValid)
    }

    func testEmptyBundleWithAxOnlyIsInvalid() {
        let report = IPCRuleValidator.validate(
            IPCRuleDefinition(bundleId: "", axSubrole: "AXStandardWindow", layout: .float)
        )
        XCTAssertNotNil(report.identifierError)
        XCTAssertFalse(report.isValid)
    }

    func testMalformedBundleIsRejected() {
        let report = IPCRuleValidator.validate(IPCRuleDefinition(bundleId: "not a bundle id"))
        XCTAssertNotNil(report.bundleIdError)
        XCTAssertFalse(report.isValid)
    }

    func testEmptyBundleStringHasNoFormatError() {
        XCTAssertNil(IPCRuleValidator.bundleIdError(for: ""))
    }

    func testIdentifyingMatcherWithoutEffectIsInvalid() {
        let report = IPCRuleValidator.validate(
            IPCRuleDefinition(bundleId: "com.test.app")
        )
        XCTAssertNotNil(report.effectError)
        XCTAssertFalse(report.isValid)
    }

    func testWorkspaceAssignmentCountsAsEffect() {
        let report = IPCRuleValidator.validate(
            IPCRuleDefinition(bundleId: "com.test.app", assignToWorkspace: "2")
        )
        XCTAssertNil(report.effectError)
        XCTAssertTrue(report.isValid)
    }

    func testBothTitleMatchersRejected() {
        let report = IPCRuleValidator.validate(
            IPCRuleDefinition(bundleId: "com.test.app", titleSubstring: "Main", titleRegex: "^Main$", layout: .float)
        )
        XCTAssertNotNil(report.titleMatcherError)
        XCTAssertFalse(report.isValid)
    }

    func testNonPositiveMinSizeRejected() {
        for value in [0.0, -10.0, Double.nan] {
            let report = IPCRuleValidator.validate(
                IPCRuleDefinition(bundleId: "com.test.app", minWidth: value)
            )
            XCTAssertNotNil(report.minSizeError, "min width \(value) should be rejected")
            XCTAssertFalse(report.isValid)
        }

        let height = IPCRuleValidator.validate(
            IPCRuleDefinition(bundleId: "com.test.app", minHeight: -1)
        )
        XCTAssertNotNil(height.minSizeError)
    }

    func testPositiveMinSizeAccepted() {
        let report = IPCRuleValidator.validate(
            IPCRuleDefinition(bundleId: "com.test.app", minWidth: 400, minHeight: 300)
        )
        XCTAssertNil(report.minSizeError)
        XCTAssertTrue(report.isValid)
    }

    func testMessagesAggregateAllErrors() {
        let report = IPCRuleValidator.validate(IPCRuleDefinition(bundleId: ""))
        XCTAssertEqual(report.messages, report.messages.filter { !$0.isEmpty })
        XCTAssertFalse(report.messages.isEmpty)
        XCTAssertTrue(report.messages.contains { $0 == report.identifierError })
    }

    func testSnapshotCodecToleratesMissingValidationMessages() throws {
        let json = """
        {"id":"x","position":1,"bundleId":"com.test.app","layout":"float","specificity":2,"isValid":true}
        """
        let snapshot = try JSONDecoder().decode(IPCRuleSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.validationMessages, [])

        let roundTripped = try JSONDecoder().decode(
            IPCRuleSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        XCTAssertEqual(roundTripped, snapshot)
    }

    func testBundleIdTrimsSurroundingWhitespace() {
        XCTAssertNil(IPCRuleValidator.bundleIdError(for: " com.example.app "))
        XCTAssertNil(IPCRuleValidator.bundleIdError(for: "com.example.app\n"))
    }

    func testBundleIdRejectsLeadingAndTrailingDots() {
        XCTAssertNotNil(IPCRuleValidator.bundleIdError(for: "com.app."))
        XCTAssertNotNil(IPCRuleValidator.bundleIdError(for: ".com.app"))
    }

    func testBundleIdRegexBoundaries() {
        XCTAssertNil(IPCRuleValidator.bundleIdError(for: "a"))
        XCTAssertNil(IPCRuleValidator.bundleIdError(for: "1"))
        XCTAssertNil(IPCRuleValidator.bundleIdError(for: "com.app-slot"))
        XCTAssertNotNil(IPCRuleValidator.bundleIdError(for: "com.app-"))
        XCTAssertNotNil(IPCRuleValidator.bundleIdError(for: "com.app slot"))
    }

    func testBundleIdRequiresWholeASCIIIdentifier() {
        let invalidIdentifiers = [
            "com.app\nother", "com.app\r\nother", "com.app\u{2028}other",
            "com.ä", "com.Ａ", "com.a\u{0301}", "com.😀", "com.app\u{0000}",
            "com..app", "com.-app", "com.app_name", "-com.app"
        ]
        for identifier in invalidIdentifiers {
            XCTAssertEqual(IPCRuleValidator.bundleIdError(for: identifier), "Invalid bundle ID format", identifier)
        }
    }

    func testBundleIdPreservesWhitespaceTrimmingAndMixedSeparators() {
        for identifier in [" \t\r\n", "\u{2003}com.App-123\u{2028}", "a-b.c-D9", "COM9"] {
            XCTAssertNil(IPCRuleValidator.bundleIdError(for: identifier), identifier)
        }
    }

    func testValidRegexReturnsNoMessage() {
        XCTAssertNil(IPCRuleValidator.invalidRegexMessage(for: "^foo.*bar$"))
        XCTAssertNil(IPCRuleValidator.invalidRegexMessage(for: nil))
        XCTAssertNil(IPCRuleValidator.invalidRegexMessage(for: "   "))
    }

    func testInvalidRegexReturnsMessage() {
        XCTAssertNotNil(IPCRuleValidator.invalidRegexMessage(for: "["))
    }

    func testMinSizeRejectsNonFiniteAndNegativeZero() {
        for value in [Double.infinity, -Double.infinity, -0.0] {
            let report = IPCRuleValidator.validate(
                IPCRuleDefinition(bundleId: "com.test.app", minWidth: value)
            )
            XCTAssertNotNil(report.minSizeError, "min width \(value) should be rejected")
        }

        let height = IPCRuleValidator.validate(
            IPCRuleDefinition(bundleId: "com.test.app", minHeight: .infinity)
        )
        XCTAssertNotNil(height.minSizeError)
    }

    func testMinSizeAcceptsSmallestPositiveFinite() {
        let one = IPCRuleValidator.validate(
            IPCRuleDefinition(bundleId: "com.test.app", minWidth: 1)
        )
        XCTAssertNil(one.minSizeError)

        let smallestPositive = IPCRuleValidator.validate(
            IPCRuleDefinition(bundleId: "com.test.app", minWidth: Double.leastNonzeroMagnitude)
        )
        XCTAssertNil(smallestPositive.minSizeError)
    }
}
