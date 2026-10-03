// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

@testable import OmniWM
import XCTest

final class AssignableCommandBindingTests: XCTestCase {
    func testEveryRegistryDefaultMapsToAnAssignableCatalogSpec() throws {
        for binding in HotkeyBindingRegistry.defaults() {
            let spec = try XCTUnwrap(
                ActionCatalog.spec(for: binding.id),
                "Missing catalog spec for \(binding.id)"
            )
            XCTAssertNotEqual(spec.visibility, .unassignable, binding.id)
        }
    }
}
