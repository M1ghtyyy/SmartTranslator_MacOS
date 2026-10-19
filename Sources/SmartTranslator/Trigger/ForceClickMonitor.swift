import AppKit

/// Detects a Force Click (pressure stage 2) anywhere in the system.
///
/// In the session event stream trackpad pressure arrives as a generic gesture
/// event (CGEvent type 29); AppKit turns it into `.pressure` / `.quickLook`
/// only when the NSEvent is created, so the tap converts every gesture event.
/// An NSEvent global monitor feeds the same handler as a second source. The tap
/// can also swallow the Look Up (quickLook) event after a force click we handled.
final class ForceClickMonitor {
    var onForceClick: ((CGPoint) -> Void)?
    var suppressLookUp = false

    private static let gestureType = UInt32(NSEvent.EventType.gesture.rawValue)
    private static let pressureType = UInt32(NSEvent.EventType.pressure.rawValue)
    private static let quickLookType = UInt32(NSEvent.EventType.quickLook.rawValue)
    /// Undocumented CGEvent field with the IOHIDEventType of a gesture event.
    private static let gestureHIDTypeField = CGEventField(rawValue: 110)!

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var diagnostic = false
    private var lastTrigger = Date.distantPast
    private var loggedFirstPressure = false
    private var lastLoggedGesture: (cgType: UInt32, nsType: UInt, hidType: Int64)?

    var isRunning: Bool { tap != nil || globalMonitor != nil }

    func start(diagnostic: Bool) {
        if isRunning && self.diagnostic == diagnostic { return }
        stop()
        self.diagnostic = diagnostic
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .pressure) { [weak self] event in
            self?.log("monitor: pressure stage=\(event.stage) pressure=\(event.pressure)")
            self?.handlePressure(stage: event.stage, source: "monitor")
        }
        installTap()
        DiagnosticsLog.shared.log("ForceClickMonitor: tap=\(tap != nil) monitor=\(globalMonitor != nil)", force: true)
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        globalMonitor = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    private func installTap() {
        var mask = CGEventMask(1) << CGEventMask(Self.gestureType)
        mask |= CGEventMask(1) << CGEventMask(Self.pressureType)
        mask |= CGEventMask(1) << CGEventMask(Self.quickLookType)
        if diagnostic {
            // Log every other event type too, to find out what a force click produces.
            let noisy: Set<CGEventType> = [
                .mouseMoved, .keyDown, .keyUp, .flagsChanged, .scrollWheel,
                .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            ]
            let noisyRaw = Set(noisy.map(\.rawValue))
            for type in UInt32(1)..<UInt32(40) where !noisyRaw.contains(type) {
                mask |= CGEventMask(1) << CGEventMask(type)
            }
        }

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<ForceClickMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handleTapEvent(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            DiagnosticsLog.shared.log("Could not create the CGEventTap — is Accessibility access granted?", force: true)
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
    }

    private func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let raw = type.rawValue
        guard [Self.gestureType, Self.pressureType, Self.quickLookType].contains(raw) else {
            log("tap: event type=\(raw)")
            return Unmanaged.passUnretained(event)
        }
        guard let nsEvent = NSEvent(cgEvent: event) else { return Unmanaged.passUnretained(event) }

        switch nsEvent.type {
        case .pressure:
            log("tap: pressure stage=\(nsEvent.stage) pressure=\(nsEvent.pressure) cgType=\(raw)")
            handlePressure(stage: nsEvent.stage, source: "tap")
        case .quickLook:
            let suppress = suppressLookUp && Date().timeIntervalSince(lastTrigger) < 1.5
            log("tap: quickLook suppressed=\(suppress)")
            if suppress { return nil }
        default:
            logGesture(event, cgType: raw, nsType: nsEvent.type.rawValue)
        }
        return Unmanaged.passUnretained(event)
    }

    private func handlePressure(stage: Int, source: String) {
        if !loggedFirstPressure {
            loggedFirstPressure = true
            DiagnosticsLog.shared.log("First pressure event received (\(source))", force: true)
        }
        // Both sources report the same press; the time window de-duplicates them.
        guard stage >= 2, Date().timeIntervalSince(lastTrigger) > 0.8 else { return }
        lastTrigger = Date()
        let location = NSEvent.mouseLocation
        DiagnosticsLog.shared.log("Force click (\(source)) at \(location)", force: true)
        onForceClick?(location)
    }

    /// Logs gesture events only when their kind changes, to keep the log readable.
    private func logGesture(_ event: CGEvent, cgType: UInt32, nsType: UInt) {
        guard diagnostic else { return }
        let hidType = event.getIntegerValueField(Self.gestureHIDTypeField)
        if let last = lastLoggedGesture, last.cgType == cgType, last.nsType == nsType, last.hidType == hidType {
            return
        }
        lastLoggedGesture = (cgType, nsType, hidType)
        DiagnosticsLog.shared.log("tap: gesture cgType=\(cgType) nsType=\(nsType) hidType=\(hidType)")
    }

    private func log(_ message: @autoclosure () -> String) {
        guard diagnostic else { return }
        DiagnosticsLog.shared.log(message())
    }
}
