// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class DisplayConfigurationTransientSampleTests: XCTestCase {
    private var sampledMonitors: [Monitor] = []

    func testObserverIgnoresUnusableSampleAsBaseline() {
        let first = makeMonitor(displayId: 1, name: "First", originX: 0, width: 1440)
        let second = makeMonitor(displayId: 2, name: "Second", originX: 1440, width: 1440)
        sampledMonitors = [first, second]
        let observer = DisplayConfigurationObserver(monitorSampler: { self.sampledMonitors })
        var events: [DisplayConfigurationObserver.DisplayEvent] = []
        observer.setEventHandler { events.append($0) }

        sampledMonitors = [makeMonitor(displayId: 1, name: "First", originX: 0, width: 1), second]
        observer.sampleNow()
        sampledMonitors = [first, second]
        observer.sampleNow()

        XCTAssertTrue(events.isEmpty)
    }

    private func makeMonitor(displayId: CGDirectDisplayID, name: String, originX: CGFloat, width: CGFloat) -> Monitor {
        let frame = CGRect(x: originX, y: 0, width: width, height: 900)
        return Monitor(
            id: .init(displayId: displayId),
            displayId: displayId,
            frame: frame,
            visibleFrame: frame,
            hasNotch: false,
            name: name
        )
    }
}
