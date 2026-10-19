import AppKit

/// Copy of every item and type on a pasteboard, so it can be restored after a simulated ⌘C.
public struct PasteboardSnapshot {
    private let items: [[(NSPasteboard.PasteboardType, Data)]]

    public init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    public var isEmpty: Bool { items.isEmpty }

    public func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entries {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restored.isEmpty {
            pasteboard.writeObjects(restored)
        }
    }
}
