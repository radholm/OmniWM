// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWMCtl
import OmniWMIPC
import XCTest

final class WindowTargetedActionIPCContractTests: XCTestCase {
    private enum TestFailure: Error {
        case unexpectedPayload
    }

    private func parseCases() throws -> [([String], IPCWindowRequest)] {
        [
            (["toggle-floating"], .init(name: .toggleFloating, windowId: "ow_x")),
            (["assign-to-scratchpad", "2"], .init(name: .assignToScratchpad, windowId: "ow_x", scratchpadIndex: 2))
        ]
    }

    func testParserBuildsEveryTargetedAction() throws {
        for (tokens, expected) in try parseCases() {
            let arguments = ["window", tokens[0], "ow_x"] + tokens.dropFirst()
            XCTAssertEqual(try parseWindowRequest(arguments), expected, "\(arguments)")
        }
    }

    func testWireWriterMatchesFoundationForEveryTargetedAction() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for (tokens, window) in try parseCases() {
            let request = IPCRequest(id: "1", window: window)
            var reference = try encoder.encode(request)
            reference.append(0x0A)
            XCTAssertEqual(try IPCWire.encodeRequestLine(request), reference, "\(tokens)")
            XCTAssertEqual(try IPCWire.decodeRequest(from: IPCWire.encodeRequestLine(request)), request, "\(tokens)")
        }
    }

    func testRoundTripKeepsFlatWireShape() throws {
        let extras: [[String: Any]] = [[:], ["scratchpadIndex": 2]]
        let cases = try parseCases()
        XCTAssertEqual(cases.count, extras.count)
        for ((tokens, request), extra) in zip(cases, extras) {
            let data = try JSONEncoder().encode(request)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            var expected: [String: Any] = ["name": tokens[0], "windowId": "ow_x"]
            expected.merge(extra) { _, value in value }
            XCTAssertTrue(NSDictionary(dictionary: object).isEqual(to: expected), "\(tokens): \(object)")
            XCTAssertEqual(try JSONDecoder().decode(IPCWindowRequest.self, from: data), request)
        }
    }

    func testExistingActionsKeepWireShape() throws {
        let data = try JSONEncoder().encode(IPCWindowRequest(name: .focus, windowId: "ow_x"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["name", "windowId"])
    }

    func testDecodeRejectsMissingRequiredKey() {
        let payloads = [
            #"{"name":"assign-to-scratchpad","windowId":"ow_x"}"#
        ]
        for payload in payloads {
            XCTAssertThrowsError(try JSONDecoder().decode(IPCWindowRequest.self, from: Data(payload.utf8)), payload)
        }
    }

    func testDecodeRejectsExtraOrWrongKey() {
        let payloads = [
            #"{"name":"toggle-floating","windowId":"ow_x","scratchpadIndex":2}"#,
            #"{"name":"focus","windowId":"ow_x","scratchpadIndex":2}"#,
            #"{"name":"assign-to-scratchpad","windowId":"ow_x","scratchpadIndex":11}"#
        ]
        for payload in payloads {
            XCTAssertThrowsError(try JSONDecoder().decode(IPCWindowRequest.self, from: Data(payload.utf8)), payload)
        }
    }

    func testParserRejectsBadArityAndBadValues() {
        let invocations = [
            ["window", "toggle-floating", "ow_x", "1"],
            ["window", "assign-to-scratchpad", "ow_x"],
            ["window", "assign-to-scratchpad", "ow_x", "two"],
            ["window", "assign-to-scratchpad", "ow_x", "0"],
            ["window", "assign-to-scratchpad", "ow_x", "11"],
            ["window", "toggle-floating"]
        ]
        for invocation in invocations {
            XCTAssertThrowsError(try CLIParser.parse(arguments: ["omniwmctl"] + invocation), "\(invocation)") { error in
                XCTAssertEqual(error as? CLIParseError, .usage(CLIParser.usageText))
            }
        }
    }

    func testHelpAndCompletionsExposeTargetedActions() throws {
        XCTAssertTrue(CLIParser.usageText.contains("omniwmctl window assign-to-scratchpad <opaque-id> <number>"))

        let names = try parseCases().map { $0.0[0] }
        for name in names {
            XCTAssertTrue(CLIParser.usageText.contains("omniwmctl window \(name) <opaque-id>"), name)
        }
        for shell in CLIShell.allCases {
            let script = CLICompletionGenerator.script(for: shell)
            for name in names {
                XCTAssertTrue(script.contains(name), "\(shell) \(name)")
            }
        }
    }

    private func parseWindowRequest(_ arguments: [String]) throws -> IPCWindowRequest {
        let parsed = try CLIParser.parse(arguments: ["omniwmctl"] + arguments)
        guard case let .window(request) = parsed.request.payload else {
            throw TestFailure.unexpectedPayload
        }
        return request
    }
}
