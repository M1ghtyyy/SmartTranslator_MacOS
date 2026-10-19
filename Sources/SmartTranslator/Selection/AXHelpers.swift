import AppKit
import ApplicationServices

enum AXHelpers {
    private static let timeout: Float = 0.25
    private static var manualAccessibilityPIDs = Set<pid_t>()

    static var frontmostPID: pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    /// PID of the app owning the topmost normal window under a point in AppKit screen coordinates.
    static func applicationPID(atScreenPoint point: CGPoint) -> pid_t? {
        guard let primary = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return nil }
        // CGWindow bounds use a top-left origin on the primary screen.
        let cgPoint = CGPoint(x: point.x, y: primary.frame.maxY - point.y)
        let ownPID = getpid()
        for info in windows {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary),
                  bounds.contains(cgPoint)
            else { continue }
            return pid
        }
        return nil
    }

    static func focusedElement(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        enableManualAccessibilityIfNeeded(app, pid: pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func selectedRange(_ element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    /// On-screen rectangle (AppKit coordinates) of the current selection, if the app exposes it.
    /// With a click point, the element under it is tried too, and rectangles far from it are rejected.
    static func selectionBounds(pid: pid_t, focused: AXUIElement?, clickPoint: CGPoint?) -> NSRect? {
        var candidates: [AXUIElement] = []
        if let focused { candidates.append(focused) }
        if let clickPoint, let element = element(at: clickPoint, pid: pid) { candidates.append(element) }
        for element in candidates {
            guard let axRect = boundsOfSelectedRange(element) ?? boundsOfSelectedTextMarkers(element) else { continue }
            let rect = appKitRect(fromAX: axRect)
            if let clickPoint {
                guard rect.insetBy(dx: -48, dy: -48).contains(clickPoint) else { continue }
            } else {
                guard NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) else { continue }
            }
            return rect
        }
        return nil
    }

    private static func element(at point: CGPoint, pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(primaryScreenHeight - point.y), &element) == .success,
              let element
        else { return nil }
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }

    /// Native text views and fields.
    private static func boundsOfSelectedRange(_ element: AXUIElement) -> CGRect? {
        guard let range = selectedRange(element), range.length > 0 else { return nil }
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &value
        ) == .success else { return nil }
        return rect(from: value)
    }

    /// Web content (Safari, Chrome) describes selections with text markers.
    private static func boundsOfSelectedTextMarkers(_ element: AXUIElement) -> CGRect? {
        var markerRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRange) == .success,
              let markerRange
        else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, "AXBoundsForTextMarkerRange" as CFString, markerRange, &value
        ) == .success else { return nil }
        return rect(from: value)
    }

    private static func rect(from value: CFTypeRef?) -> CGRect? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    /// Accessibility uses a top-left origin on the primary screen; AppKit a bottom-left one.
    private static var primaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    private static func appKitRect(fromAX rect: CGRect) -> NSRect {
        NSRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Chromium and Electron apps build their accessibility tree only when asked.
    private static func enableManualAccessibilityIfNeeded(_ app: AXUIElement, pid: pid_t) {
        guard !manualAccessibilityPIDs.contains(pid) else { return }
        manualAccessibilityPIDs.insert(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }
}
