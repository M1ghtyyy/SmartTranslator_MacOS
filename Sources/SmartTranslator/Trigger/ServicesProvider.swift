import AppKit

/// Handles "Services → Translate with SmartTranslator" (declared under NSServices in Info.plist).
final class ServicesProvider: NSObject {
    var onText: ((String) -> Void)?

    @objc func translateSelection(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            error.pointee = "No text selected" as NSString
            return
        }
        DiagnosticsLog.shared.log("Services: received text (\(text.count) chars)", force: true)
        onText?(text)
    }
}
