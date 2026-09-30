// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation

extension SkyLight {
    func captureWallpaper(in frame: CGRect) -> CGImage? {
        guard let capture = surfaces.captureWindowList,
              let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]],
              var windowId = Self.wallpaperWindowId(in: windows, frame: frame),
              let images = capture(getMainConnectionID(), &windowId, 1, (1 << 11) | (1 << 9) | (1 << 19))?
              .takeRetainedValue()
        else { return nil }
        return Self.firstCapturedImage(in: images)
    }

    func captureWindow(_ windowId: UInt32) -> CGImage? {
        var windowId = windowId
        guard let capture = surfaces.captureWindowList,
              let images = capture(getMainConnectionID(), &windowId, 1, (1 << 11) | (1 << 19))?.takeRetainedValue()
        else { return nil }
        return Self.firstCapturedImage(in: images).flatMap { $0.width > 1 && $0.height > 1 ? $0 : nil }
    }

    static func wallpaperWindowId(in windows: [[String: Any]], frame: CGRect) -> UInt32? {
        for window in windows {
            guard let level = window[kCGWindowLayer as String] as? Int32,
                  level == CGWindowLevelForKey(.desktopWindow) - 1,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let windowFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  windowFrame == frame,
                  let windowId = window[kCGWindowNumber as String] as? UInt32
            else { continue }
            return windowId
        }
        return nil
    }

    static func firstCapturedImage(in images: CFArray) -> CGImage? {
        guard CFArrayGetCount(images) == 1,
              let pointer = CFArrayGetValueAtIndex(images, 0)
        else { return nil }
        let value = Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
        guard CFGetTypeID(value) == CGImage.typeID else { return nil }
        return unsafeDowncast(value, to: CGImage.self)
    }
}
