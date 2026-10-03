// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation

public struct IPCRuleValidationReport: Equatable, Sendable {
    public let bundleIdError: String?
    public let invalidRegexMessage: String?
    public let identifierError: String?
    public let titleMatcherError: String?
    public let effectError: String?
    public let minSizeError: String?

    public init(
        bundleIdError: String?,
        invalidRegexMessage: String?,
        identifierError: String? = nil,
        titleMatcherError: String? = nil,
        effectError: String? = nil,
        minSizeError: String? = nil
    ) {
        self.bundleIdError = bundleIdError
        self.invalidRegexMessage = invalidRegexMessage
        self.identifierError = identifierError
        self.titleMatcherError = titleMatcherError
        self.effectError = effectError
        self.minSizeError = minSizeError
    }

    public var messages: [String] {
        [bundleIdError, invalidRegexMessage, identifierError, titleMatcherError, effectError, minSizeError]
            .compactMap { $0 }
    }

    public var isValid: Bool {
        messages.isEmpty
    }
}

public enum IPCRuleValidator {
    public static func bundleIdError(for bundleId: String) -> String? {
        let trimmed = bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard trimmed.wholeMatch(of: /[a-zA-Z0-9]+(?:[.-][a-zA-Z0-9]+)*/) != nil else {
            return "Invalid bundle ID format"
        }
        return nil
    }

    public static func identifierError(for rule: IPCRuleDefinition) -> String? {
        let hasAnchor = nonEmpty(rule.bundleId)
            || nonEmpty(rule.appNameSubstring)
            || nonEmpty(rule.titleSubstring)
            || nonEmpty(rule.titleRegex)
        return hasAnchor ? nil : "Set a bundle ID, app name, or title matcher"
    }

    public static func titleMatcherError(for rule: IPCRuleDefinition) -> String? {
        guard nonEmpty(rule.titleSubstring), nonEmpty(rule.titleRegex) else { return nil }
        return "Use either a title substring or a title regex, not both"
    }

    public static func effectError(for rule: IPCRuleDefinition) -> String? {
        let hasEffect = rule.layout != .auto
            || nonEmpty(rule.assignToWorkspace)
            || rule.minWidth != nil
            || rule.minHeight != nil
        return hasEffect
            ? nil
            : "Set a layout, workspace, or minimum size — this rule has no effect"
    }

    public static func minSizeError(for rule: IPCRuleDefinition) -> String? {
        if let width = rule.minWidth, !(width.isFinite && width > 0) {
            return "Minimum width must be a positive number"
        }
        if let height = rule.minHeight, !(height.isFinite && height > 0) {
            return "Minimum height must be a positive number"
        }
        return nil
    }

    private static func nonEmpty(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func invalidRegexMessage(for pattern: String?) -> String? {
        guard let pattern = pattern?.trimmingCharacters(in: .whitespacesAndNewlines), !pattern.isEmpty else {
            return nil
        }

        do {
            _ = try NSRegularExpression(pattern: pattern)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    public static func validate(_ rule: IPCRuleDefinition) -> IPCRuleValidationReport {
        IPCRuleValidationReport(
            bundleIdError: bundleIdError(for: rule.bundleId),
            invalidRegexMessage: invalidRegexMessage(for: rule.titleRegex),
            identifierError: identifierError(for: rule),
            titleMatcherError: titleMatcherError(for: rule),
            effectError: effectError(for: rule),
            minSizeError: minSizeError(for: rule)
        )
    }
}
