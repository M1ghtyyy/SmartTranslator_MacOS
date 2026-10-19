import AppKit

/// Appends to ~/Library/Logs/SmartTranslator.log. Verbose lines only when diagnostics are on.
final class DiagnosticsLog {
    static let shared = DiagnosticsLog()

    var enabled = false
    let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/SmartTranslator.log")

    private let queue = DispatchQueue(label: "SmartTranslator.DiagnosticsLog")
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    func log(_ message: @autoclosure () -> String, force: Bool = false) {
        guard enabled || force else { return }
        let line = "\(formatter.string(from: Date())) \(message())\n"
        let url = fileURL
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    func reveal() {
        queue.sync {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
        }
        NSWorkspace.shared.open(fileURL)
    }
}
