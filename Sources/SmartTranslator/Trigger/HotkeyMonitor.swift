import Carbon
import Foundation

struct Hotkey: Identifiable, Hashable {
    let id: String
    let title: String
    let keyCode: UInt32
    let modifiers: UInt32

    static let offID = "off"
    static let defaultID = "ctrl-opt-t"

    static let all: [Hotkey] = [
        Hotkey(id: "ctrl-opt-t", title: "⌃⌥T", keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey)),
        Hotkey(id: "opt-cmd-t", title: "⌥⌘T", keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(optionKey | cmdKey)),
        Hotkey(id: "ctrl-cmd-t", title: "⌃⌘T", keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | cmdKey)),
    ]

    static func byID(_ id: String) -> Hotkey? {
        all.first { $0.id == id }
    }
}

/// Global hotkey via Carbon `RegisterEventHotKey` (needs no extra permissions).
final class HotkeyMonitor {
    var onHotkey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var registered: Hotkey?

    func register(_ hotkey: Hotkey?) {
        guard hotkey != registered || (hotkey != nil && hotKeyRef == nil) else { return }
        unregister()
        guard let hotkey else { return }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x534D_5452), id: 1) // "SMTR"
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status == noErr {
            registered = hotkey
        } else {
            DiagnosticsLog.shared.log("Could not register hotkey \(hotkey.title): \(status)", force: true)
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        registered = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                Unmanaged<HotkeyMonitor>.fromOpaque(userData).takeUnretainedValue().onHotkey?()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }
}
