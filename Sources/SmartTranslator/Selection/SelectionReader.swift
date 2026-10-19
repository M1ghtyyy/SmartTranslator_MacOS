import AppKit
import SmartTranslatorCore

struct SelectedText {
    let text: String
    let context: String?
    /// On-screen rectangle of the selection (AppKit coordinates), when the app exposes it.
    var bounds: NSRect?
}

enum SelectionTrigger {
    case forceClick(CGPoint)
    case explicit
}

/// Reads the selected text of another app: Accessibility first, simulated ⌘C as a fallback.
@MainActor
enum SelectionReader {
    static func read(trigger: SelectionTrigger) async -> SelectedText? {
        let pid: pid_t?
        let clickPoint: CGPoint?
        switch trigger {
        case .forceClick(let point):
            // The app under the cursor may not be frontmost yet right after the click.
            pid = AXHelpers.applicationPID(atScreenPoint: point) ?? AXHelpers.frontmostPID
            clickPoint = point
        case .explicit:
            pid = AXHelpers.frontmostPID
            clickPoint = nil
        }
        guard let pid, pid != getpid() else { return nil }

        let focused = AXHelpers.focusedElement(pid: pid)
        var selection: SelectedText
        if let focused,
           let text = AXHelpers.string(focused, kAXSelectedTextAttribute),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selection = SelectedText(text: text, context: context(of: focused))
            DiagnosticsLog.shared.log("Selection via Accessibility (\(text.count) chars)", force: true)
        } else {
            if clickPoint == nil {
                await waitForModifierRelease()
            }
            guard let copied = await copyViaKeystroke(),
                  !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            selection = SelectedText(text: copied, context: nil)
            DiagnosticsLog.shared.log("Selection via ⌘C (\(copied.count) chars)", force: true)
        }

        selection.bounds = AXHelpers.selectionBounds(pid: pid, focused: focused, clickPoint: clickPoint)
        DiagnosticsLog.shared.log("Selection bounds: \(selection.bounds.map { "\($0)" } ?? "none, panel at the cursor")")
        return selection
    }

    private static func context(of element: AXUIElement) -> String? {
        guard let range = AXHelpers.selectedRange(element), range.length > 0,
              let value = AXHelpers.string(element, kAXValueAttribute),
              (value as NSString).length < 200_000
        else { return nil }
        return ContextExtractor.surroundingText(in: value, selection: range)
    }

    private static func copyViaKeystroke() async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        let initialChangeCount = pasteboard.changeCount

        postCommandC()
        let deadline = Date().addingTimeInterval(0.35)
        while pasteboard.changeCount == initialChangeCount && Date() < deadline {
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
        guard pasteboard.changeCount != initialChangeCount else { return nil }
        // Some apps write several representations one after another.
        try? await Task.sleep(nanoseconds: 30_000_000)

        let text = isTextSelectionCopy(pasteboard) ? pasteboard.string(forType: .string) : nil
        snapshot.restore(to: pasteboard)
        return text
    }

    private static func isTextSelectionCopy(_ pasteboard: NSPasteboard) -> Bool {
        // Finder copies selected files, whose names come along as plain text.
        if pasteboard.types?.contains(.fileURL) == true { return false }
        return !isEmptySelectionCopy(pasteboard)
    }

    private static func postCommandC() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyC: CGKeyCode = 8 // kVK_ANSI_C; apps map it to ⌘C in any keyboard layout
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    /// VS Code copies the whole current line when nothing is selected.
    private static func isEmptySelectionCopy(_ pasteboard: NSPasteboard) -> Bool {
        guard let type = pasteboard.types?.first(where: { $0.rawValue.contains("vscode-editor-data") }),
              let data = pasteboard.string(forType: type)
        else { return false }
        return data.replacingOccurrences(of: " ", with: "").contains("\"isFromEmptySelection\":true")
    }

    /// After a hotkey the user may still hold ⌃/⌥, which would turn ⌘C into another shortcut.
    private static func waitForModifierRelease() async {
        let held: CGEventFlags = [.maskControl, .maskAlternate, .maskShift]
        let deadline = Date().addingTimeInterval(0.4)
        while !CGEventSource.flagsState(.hidSystemState).intersection(held).isEmpty && Date() < deadline {
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
    }
}
