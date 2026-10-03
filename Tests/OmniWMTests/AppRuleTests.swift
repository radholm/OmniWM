// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

final class AppRuleTests: XCTestCase {
    func testNormalizeSingleTitleDropsSubstringWhenBothSet() {
        let rule = AppRule(
            bundleId: "com.test.app",
            titleSubstring: "Main",
            titleRegex: "^Main$",
            layout: .float
        )
        XCTAssertNil(rule.titleSubstring)
        XCTAssertEqual(rule.titleRegex, "^Main$")
    }

    func testNormalizeKeepsLoneTitleMatchers() {
        let substring = AppRule(bundleId: "a", titleSubstring: "Main", layout: .float)
        XCTAssertEqual(substring.titleSubstring, "Main")
        XCTAssertNil(substring.titleRegex)

        let regex = AppRule(bundleId: "a", titleRegex: "^Main$", layout: .float)
        XCTAssertNil(regex.titleSubstring)
        XCTAssertEqual(regex.titleRegex, "^Main$")
    }

    func testNormalizeSingleTitleAppliesOnDecode() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","bundleId":"com.test.app",\
        "titleSubstring":"Main","titleRegex":"^Main$","layout":"float"}
        """
        let rule = try JSONDecoder().decode(AppRule.self, from: Data(json.utf8))
        XCTAssertNil(rule.titleSubstring)
        XCTAssertEqual(rule.titleRegex, "^Main$")
    }

    func testHasEffect() {
        XCTAssertFalse(AppRule(bundleId: "com.test.app").hasEffect)
        XCTAssertFalse(AppRule(bundleId: "com.test.app", appNameSubstring: "Test").hasEffect)
        XCTAssertTrue(AppRule(bundleId: "com.test.app", layout: .float).hasEffect)
        XCTAssertTrue(AppRule(bundleId: "com.test.app", assignToWorkspace: "2").hasEffect)
        XCTAssertTrue(AppRule(bundleId: "com.test.app", minWidth: 400).hasEffect)
        XCTAssertTrue(AppRule(bundleId: "com.test.app", minHeight: 300).hasEffect)
    }

    @MainActor
    func testAppRulesRevisionChangesOnlyForDistinctRules() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniWMRuleRevision-\(UUID().uuidString)", isDirectory: true)
        let settings = SettingsStore(
            persistence: SettingsFilePersistence(
                directory: root.appendingPathComponent("config", isDirectory: true),
                startWatching: false,
                deferSaves: false
            ),
            runtimeState: RuntimeStateStore(
                directory: root.appendingPathComponent("state", isDirectory: true),
                deferSaves: false
            ),
            autosaveEnabled: false
        )
        let baseline = settings.appRulesRevision
        let rules = [AppRule(bundleId: "com.test.app", layout: .float)]

        settings.appRules = rules
        XCTAssertEqual(settings.appRulesRevision, baseline + 1)

        settings.appRules = rules
        XCTAssertEqual(settings.appRulesRevision, baseline + 1)
    }

    func testSelectingBundledApplicationReplacesOnlyApplicationIdentityMatchers() {
        var draft = populatedDraft()
        let expectedId = draft.id

        draft.selectApplication(bundleId: "com.example.Bundled", appName: "Bundled")

        XCTAssertEqual(draft.id, expectedId)
        XCTAssertEqual(draft.bundleId, "com.example.Bundled")
        XCTAssertFalse(draft.appNameMatcherEnabled)
        XCTAssertEqual(draft.appNameSubstring, "")
        assertUnrelatedSelectionState(draft)
    }

    func testSelectingBundlelessApplicationReplacesOnlyApplicationIdentityMatchers() {
        var draft = populatedDraft()
        let expectedId = draft.id

        draft.selectApplication(bundleId: nil, appName: "Bundleless")

        XCTAssertEqual(draft.id, expectedId)
        XCTAssertEqual(draft.bundleId, "")
        XCTAssertTrue(draft.appNameMatcherEnabled)
        XCTAssertEqual(draft.appNameSubstring, "Bundleless")
        assertUnrelatedSelectionState(draft)
    }

    func testDraftEqualityAndRuleRepresentationTrackRetainedFields() {
        let rule = AppRule(bundleId: "com.test.app")
        let lhs = AppRuleDraft(rule: rule)
        let rhs = AppRuleDraft(rule: rule)

        XCTAssertEqual(lhs, rhs)
        XCTAssertTrue(lhs.represents(rule))

        var changed = lhs
        changed.assignToWorkspaceEnabled = true
        changed.assignToWorkspace = "work"
        XCTAssertNotEqual(changed, rhs)
        XCTAssertFalse(changed.represents(rule))
    }

    private func populatedDraft() -> AppRuleDraft {
        var draft = AppRuleDraft(bundleId: "com.example.Previous")
        draft.layoutAction = .float
        draft.assignToWorkspaceEnabled = true
        draft.assignToWorkspace = "work"
        draft.minWidthEnabled = true
        draft.minWidth = 640
        draft.minHeightEnabled = true
        draft.minHeight = 480
        draft.appNameMatcherEnabled = true
        draft.appNameSubstring = "Previous"
        draft.titleMatcherMode = .regex
        draft.titleSubstring = "unchanged substring"
        draft.titleRegex = "^Document"
        draft.axRoleEnabled = true
        draft.axRole = "AXWindow"
        draft.axSubroleEnabled = true
        draft.axSubrole = "AXStandardWindow"
        return draft
    }

    private func assertUnrelatedSelectionState(_ draft: AppRuleDraft) {
        XCTAssertEqual(draft.layoutAction, .float)
        XCTAssertTrue(draft.assignToWorkspaceEnabled)
        XCTAssertEqual(draft.assignToWorkspace, "work")
        XCTAssertTrue(draft.minWidthEnabled)
        XCTAssertEqual(draft.minWidth, 640)
        XCTAssertTrue(draft.minHeightEnabled)
        XCTAssertEqual(draft.minHeight, 480)
        XCTAssertEqual(draft.titleMatcherMode, .regex)
        XCTAssertEqual(draft.titleSubstring, "unchanged substring")
        XCTAssertEqual(draft.titleRegex, "^Document")
        XCTAssertTrue(draft.axRoleEnabled)
        XCTAssertEqual(draft.axRole, "AXWindow")
        XCTAssertTrue(draft.axSubroleEnabled)
        XCTAssertEqual(draft.axSubrole, "AXStandardWindow")
    }
}
