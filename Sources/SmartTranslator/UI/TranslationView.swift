import SwiftUI

struct TranslationView: View {
    @ObservedObject var model: TranslationViewModel
    let onCopy: () -> Void
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    static func render(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }

    /// Takes its natural height; the panel controller measures it with `sizeThatFits`.
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            Divider().opacity(0.6)
            content
                .animation(.easeOut(duration: 0.22), value: model.text.isEmpty)
                .animation(.easeOut(duration: 0.22), value: model.error)
            if !model.footer.isEmpty {
                Text(model.footer)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 11 + (model.placement == .below ? PanelShape.arrowSize.height : 0))
        .padding(.bottom, 11 + (model.placement == .above ? PanelShape.arrowSize.height : 0))
        .frame(width: model.cardWidth, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(model.source)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !model.text.isEmpty && model.error == nil {
                IconButton(systemName: model.copied ? "checkmark" : "doc.on.doc", help: "Copy translation", action: onCopy)
            }
            IconButton(systemName: "xmark", help: "Close (Esc)", action: onClose)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = model.error {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error)
                        .font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Open Settings", action: onOpenSettings)
                    .buttonStyle(.link)
                    .font(.system(size: 12))
            }
            .transition(.opacity)
        } else if model.text.isEmpty {
            TypingIndicator()
                .frame(height: 20)
                .transition(.opacity)
        } else {
            // The whole text when it fits in the height the panel offers, otherwise a scroll view.
            ViewThatFits(in: .vertical) {
                translation
                ScrollView { translation }
            }
            .transition(.opacity.combined(with: .offset(y: 3)))
        }
    }

    private var translation: some View {
        Text(Self.render(model.text))
            .font(.system(size: 14))
            .lineSpacing(2.5)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10.5, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(isHovered ? 0.1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? .primary : .secondary)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .help(help)
    }
}

/// Three softly pulsing dots while the translation is on its way.
private struct TypingIndicator: View {
    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    let phase = sin(time * 2 * .pi / 1.1 - Double(index) * 0.7)
                    Circle()
                        .frame(width: 6, height: 6)
                        .opacity(0.25 + 0.6 * max(0, phase))
                        .scaleEffect(0.85 + 0.15 * max(0, phase))
                }
            }
            .foregroundStyle(.secondary)
        }
    }
}
