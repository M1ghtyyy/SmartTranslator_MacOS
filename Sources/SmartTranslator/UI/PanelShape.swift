import AppKit
import SwiftUI

/// Rounded card with a popover arrow on the top or bottom edge (y-down coordinates).
struct PanelShape: Shape {
    static let arrowSize = CGSize(width: 20, height: 9)
    static let cornerRadius: CGFloat = 12

    /// Arrow tip position from the left edge.
    var arrowX: CGFloat
    var arrowOnTop: Bool

    func path(in rect: CGRect) -> Path {
        let arrow = Self.arrowSize
        let body = CGRect(
            x: rect.minX,
            y: arrowOnTop ? rect.minY + arrow.height : rect.minY,
            width: rect.width,
            height: rect.height - arrow.height
        )
        let radius = min(Self.cornerRadius, body.height / 2, body.width / 2)
        let tipX = min(max(rect.minX + arrowX, body.minX + radius + arrow.width / 2),
                       body.maxX - radius - arrow.width / 2)

        var path = Path()
        path.move(to: CGPoint(x: body.minX + radius, y: body.minY))
        if arrowOnTop {
            addArrow(to: &path, tipX: tipX, baseY: body.minY, tipY: rect.minY, leftToRight: true)
        }
        path.addLine(to: CGPoint(x: body.maxX - radius, y: body.minY))
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY),
                    tangent2End: CGPoint(x: body.maxX, y: body.minY + radius), radius: radius)
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - radius))
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY),
                    tangent2End: CGPoint(x: body.maxX - radius, y: body.maxY), radius: radius)
        if !arrowOnTop {
            addArrow(to: &path, tipX: tipX, baseY: body.maxY, tipY: rect.maxY, leftToRight: false)
        }
        path.addLine(to: CGPoint(x: body.minX + radius, y: body.maxY))
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY),
                    tangent2End: CGPoint(x: body.minX, y: body.maxY - radius), radius: radius)
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + radius))
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY),
                    tangent2End: CGPoint(x: body.minX + radius, y: body.minY), radius: radius)
        path.closeSubpath()
        return path
    }

    /// Straight sides with a softly rounded tip.
    private func addArrow(to path: inout Path, tipX: CGFloat, baseY: CGFloat, tipY: CGFloat, leftToRight: Bool) {
        let halfWidth = Self.arrowSize.width / 2
        let direction: CGFloat = leftToRight ? 1 : -1
        let towardBase: CGFloat = baseY > tipY ? 1.6 : -1.6
        path.addLine(to: CGPoint(x: tipX - halfWidth * direction, y: baseY))
        path.addLine(to: CGPoint(x: tipX - 2 * direction, y: tipY + towardBase))
        path.addQuadCurve(to: CGPoint(x: tipX + 2 * direction, y: tipY + towardBase),
                          control: CGPoint(x: tipX, y: tipY))
        path.addLine(to: CGPoint(x: tipX + halfWidth * direction, y: baseY))
    }

    /// Mask for NSVisualEffectView. Only the straight middle stretches, so the
    /// shape stays correct while the window height animates.
    func maskImage(width: CGFloat) -> NSImage {
        let arrowHeight = Self.arrowSize.height
        let topCap = (arrowOnTop ? arrowHeight : 0) + Self.cornerRadius + 1
        let bottomCap = (arrowOnTop ? 0 : arrowHeight) + Self.cornerRadius + 1
        let shape = self
        let image = NSImage(size: NSSize(width: width, height: topCap + bottomCap + 1), flipped: true) { rect in
            NSColor.black.setFill()
            NSBezierPath(cgPath: shape.path(in: rect).cgPath).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: topCap, left: 0, bottom: bottomCap, right: 0)
        image.resizingMode = .stretch
        return image
    }
}

/// Panel content: behind-window blur masked to the card shape, SwiftUI content, hairline border.
final class PanelContainerView: NSView {
    private let effectView = NSVisualEffectView()
    private let borderView = PanelBorderView()
    private var maskKey: (width: CGFloat, arrowX: CGFloat, arrowOnTop: Bool)?

    init(content: NSView) {
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 100))
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        for view in [effectView, content, borderView] {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(width: CGFloat, arrowX: CGFloat, arrowOnTop: Bool) {
        if let key = maskKey, key.width == width, key.arrowX == arrowX, key.arrowOnTop == arrowOnTop { return }
        maskKey = (width, arrowX, arrowOnTop)
        let shape = PanelShape(arrowX: arrowX, arrowOnTop: arrowOnTop)
        effectView.maskImage = shape.maskImage(width: width)
        borderView.shape = shape
    }
}

private final class PanelBorderView: NSView {
    var shape = PanelShape(arrowX: 0, arrowOnTop: true) {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setStroke()
        let path = NSBezierPath(cgPath: shape.path(in: bounds.insetBy(dx: 0.5, dy: 0.5)).cgPath)
        path.lineWidth = 1
        path.stroke()
    }
}
