import AppKit
import Combine
import SwiftUI

enum PanelPlacement {
    case below
    case above
}

@MainActor
final class TranslationViewModel: ObservableObject {
    @Published var source = ""
    @Published var text = ""
    @Published var error: String?
    @Published var footer = ""
    @Published var copied = false
    @Published var placement = PanelPlacement.below
    @Published var cardWidth: CGFloat = 340

    func reset(source: String, footer: String, width: CGFloat) {
        self.source = source
        self.footer = footer
        cardWidth = width
        text = ""
        error = nil
        copied = false
    }
}

final class TranslationPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Floating, non-activating popover under the selected phrase: the source app keeps focus.
@MainActor
final class TranslationPanelController {
    let model = TranslationViewModel()
    var onOpenSettings: (() -> Void)?
    var onClose: (() -> Void)?

    private static let gap: CGFloat = 3
    private static let initialHeight: CGFloat = 92
    private static let maxHeight: CGFloat = 520

    private var panel: TranslationPanel?
    private var container: PanelContainerView?
    private var hostingController: NSHostingController<TranslationView>?
    private var modelObserver: AnyCancellable?
    private var isSizeUpdateScheduled = false
    private var anchorRect = NSRect.zero
    private var pointerX: CGFloat = 0
    private var maxCardHeight = maxHeight
    private var cardSize = CGSize.zero
    private var frameAnimator: WindowFrameAnimator?
    private var generation = 0
    private var monitors: [Any] = []

    private(set) var isShown = false
    var frame: NSRect { panel?.frame ?? .zero }

    /// - Parameter selectionBounds: on-screen rectangle of the selected text, if the app exposes it.
    func show(near point: CGPoint, selectionBounds: NSRect? = nil) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        generation += 1
        isShown = true

        // Under the selected phrase when its bounds are known, otherwise under the cursor's line.
        if let bounds = selectionBounds, bounds.height <= 200 {
            anchorRect = bounds
            pointerX = bounds.width > 12 ? min(max(point.x, bounds.minX + 6), bounds.maxX - 6) : bounds.midX
        } else {
            anchorRect = NSRect(x: point.x, y: point.y - 11, width: 0, height: 22)
            pointerX = point.x
        }
        let visible = screenFrame(for: point)
        let spaceBelow = anchorRect.minY - visible.minY - Self.gap - 8
        let spaceAbove = visible.maxY - anchorRect.maxY - Self.gap - 8
        model.placement = spaceBelow >= 260 || spaceBelow >= spaceAbove ? .below : .above
        maxCardHeight = min(Self.maxHeight, max(140, model.placement == .below ? spaceBelow : spaceAbove))

        cardSize = measuredSize()
        let target = layoutFrame(for: cardSize)
        let slide: CGFloat = model.placement == .below ? 8 : -8
        frameAnimator?.stop()
        panel.alphaValue = 0
        panel.setFrame(target.offsetBy(dx: 0, dy: slide), display: false)
        placeContent()
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        frameAnimator?.animate(to: target, duration: 0.3)
        installMonitors()
    }

    func showMessage(_ message: String, near point: CGPoint) {
        model.reset(source: "SmartTranslator", footer: "", width: 340)
        model.error = message
        show(near: point)
    }

    func close(reason: String = "") {
        guard let panel, isShown else { return }
        DiagnosticsLog.shared.log("Panel closed: \(reason)")
        isShown = false
        removeMonitors()
        onClose?()
        generation += 1
        let closing = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }
        // Not the animation's completion handler: it isn't reliably called for borderless panels.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            guard let self, self.generation == closing else { return }
            self.frameAnimator?.stop()
            self.panel?.orderOut(nil)
        }
    }

    private func makePanel() -> TranslationPanel {
        let panel = TranslationPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: Self.initialHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.onCancel = { [weak self] in self?.close(reason: "Esc in panel") }

        let view = TranslationView(
            model: model,
            onCopy: { [weak self] in self?.copy() },
            onClose: { [weak self] in self?.close(reason: "close button") },
            onOpenSettings: { [weak self] in
                self?.close(reason: "settings")
                self?.onOpenSettings?()
            }
        )
        let hostingController = NSHostingController(rootView: view)
        hostingController.sizingOptions = []
        let container = PanelContainerView(content: hostingController.view)
        panel.contentView = container
        self.container = container
        self.hostingController = hostingController
        frameAnimator = WindowFrameAnimator(window: panel)

        // objectWillChange fires before the new value is stored and many times per
        // streamed chunk, so measure once on the next turn of the run loop.
        modelObserver = model.objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isSizeUpdateScheduled else { return }
                self.isSizeUpdateScheduled = true
                DispatchQueue.main.async { [weak self] in
                    self?.isSizeUpdateScheduled = false
                    self?.updateSize()
                }
            }
        }
        return panel
    }

    /// Natural size of the card, capped by the room next to the selection.
    private func measuredSize() -> CGSize {
        let width = model.cardWidth
        let fitting = hostingController?.sizeThatFits(in: CGSize(width: width, height: maxCardHeight))
        let height = min(ceil(fitting?.height ?? Self.initialHeight), maxCardHeight)
        return CGSize(width: width, height: max(height, 40))
    }

    /// Grows (or shrinks) the panel smoothly as the translation streams in.
    private func updateSize() {
        guard isShown else { return }
        let size = measuredSize()
        guard size != cardSize else { return }
        cardSize = size
        placeContent()
        // Retargets an animation still in flight (e.g. the appearing slide) without a jump.
        frameAnimator?.animate(to: layoutFrame(for: size), duration: 0.22)
    }

    /// Gives the SwiftUI content exactly the card size, pinned to the arrow side, so the
    /// window can animate to the new height while the content stays in place.
    private func placeContent() {
        guard let container, let view = hostingController?.view else { return }
        let below = model.placement == .below
        let y = below ? container.bounds.height - cardSize.height : 0
        view.frame = NSRect(x: 0, y: y, width: cardSize.width, height: cardSize.height)
        // Non-flipped coordinates: a flexible bottom margin keeps the top edge in place.
        view.autoresizingMask = below ? [.minYMargin] : [.maxYMargin]
    }

    private func layoutFrame(for size: CGSize) -> NSRect {
        let visible = screenFrame(for: CGPoint(x: pointerX, y: anchorRect.midY))
        var x = pointerX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        var y = model.placement == .below
            ? anchorRect.minY - Self.gap - size.height
            : anchorRect.maxY + Self.gap
        y = min(max(y, visible.minY + 8), visible.maxY - size.height - 8)
        container?.configure(width: size.width, arrowX: pointerX - x, arrowOnTop: model.placement == .below)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func screenFrame(for point: CGPoint) -> NSRect {
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        return screen?.visibleFrame ?? .zero
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(String(TranslationView.render(model.text).characters), forType: .string)
        model.copied = true
    }

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        // Clicks in other apps close the panel; clicks inside it are local events.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.frame.contains(NSEvent.mouseLocation) else { return }
                self.close(reason: "click outside")
            }
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return } // Esc
            Task { @MainActor in self?.close(reason: "Esc") }
        }) {
            monitors.append(monitor)
        }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }
}

/// Moves and resizes a window with an ease-out curve, driven by a timer.
/// A new target restarts from the current frame, so streaming updates chain smoothly.
@MainActor
final class WindowFrameAnimator {
    private weak var window: NSWindow?
    private var timer: Timer?
    private var startFrame = NSRect.zero
    private var targetFrame = NSRect.zero
    private var startTime: CFTimeInterval = 0
    private var duration: CFTimeInterval = 0.2

    init(window: NSWindow) {
        self.window = window
    }

    func animate(to target: NSRect, duration: CFTimeInterval) {
        guard let window else { return }
        startFrame = window.frame
        targetFrame = target
        startTime = CACurrentMediaTime()
        self.duration = duration
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        step()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func step() {
        guard let window else { return stop() }
        let progress = min(1, (CACurrentMediaTime() - startTime) / duration)
        let eased = 1 - pow(1 - progress, 3)
        func mix(_ from: CGFloat, _ to: CGFloat) -> CGFloat { from + (to - from) * eased }
        let frame = NSRect(
            x: mix(startFrame.minX, targetFrame.minX),
            y: mix(startFrame.minY, targetFrame.minY),
            width: mix(startFrame.width, targetFrame.width),
            height: mix(startFrame.height, targetFrame.height)
        )
        window.setFrame(window.backingAlignedRect(frame, options: .alignAllEdgesNearest), display: true)
        if progress >= 1 {
            stop()
            window.invalidateShadow()
        }
    }
}
