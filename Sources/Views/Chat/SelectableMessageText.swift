import SwiftUI
import UIKit

/// Message text with native range selection (long-press a word, drag the handles), like selecting text
/// in the desktop transcript. The edit menu adds "Quote" next to Copy, matching the desktop selection toolbar.
struct SelectableMessageText: UIViewRepresentable {
    let attributed: NSAttributedString
    var onQuote: ((String) -> Void)?

    init(markdown: String, font: UIFont, color: UIColor, lineSpacing: CGFloat, codeBackground: UIColor, linkColor: UIColor, onQuote: ((String) -> Void)? = nil) {
        let key = "md|\(font.fontName)|\(font.pointSize)|\(Self.colorKey(color))|\(lineSpacing)|\(Self.colorKey(codeBackground))|\(markdown)" as NSString
        if let cached = Self.renderCache.object(forKey: key) {
            self.attributed = cached
        } else {
            let rendered = Self.render(markdown: markdown, font: font, color: color, lineSpacing: lineSpacing, codeBackground: codeBackground)
            Self.renderCache.setObject(rendered, forKey: key, cost: markdown.utf16.count)
            self.attributed = rendered
        }
        self.linkColor = linkColor
        self.onQuote = onQuote
    }

    init(plain: String, font: UIFont, color: UIColor, lineSpacing: CGFloat, linkColor: UIColor, onQuote: ((String) -> Void)? = nil) {
        let key = "txt|\(font.fontName)|\(font.pointSize)|\(Self.colorKey(color))|\(lineSpacing)|\(plain)" as NSString
        if let cached = Self.renderCache.object(forKey: key) {
            self.attributed = cached
        } else {
            let rendered = NSAttributedString(string: plain, attributes: Self.baseAttributes(font: font, color: color, lineSpacing: lineSpacing))
            Self.renderCache.setObject(rendered, forKey: key, cost: plain.utf16.count)
            self.attributed = rendered
        }
        self.linkColor = linkColor
        self.onQuote = onQuote
    }

    private let linkColor: UIColor

    /// Chat bodies are re-evaluated on every relayout (the running timer ticks each second), so parsed
    /// markdown is reused instead of re-rendered for every message on every pass.
    private static let renderCache: NSCache<NSString, NSAttributedString> = {
        let cache = NSCache<NSString, NSAttributedString>()
        cache.totalCostLimit = 8_000_000
        return cache
    }()

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.dataDetectorTypes = []
        tv.adjustsFontForContentSizeCategory = false
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.required, for: .vertical)
        tv.delegate = context.coordinator
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.onQuote = onQuote
        tv.linkTextAttributes = [.foregroundColor: linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        tv.tintColor = linkColor
        if context.coordinator.text !== attributed {
            context.coordinator.text = attributed
            context.coordinator.measured.removeAll()
            tv.attributedText = attributed
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let proposed = proposal.width ?? UIScreen.main.bounds.width
        guard proposed > 0, proposed.isFinite else { return nil }
        // Proposals jitter by fractions of a point between passes; measuring at whole points keeps the
        // answer stable, so the cache hits and the result can't feed back into another layout pass.
        let maxWidth = max(1, floor(proposed))
        let coordinator = context.coordinator
        if coordinator.text !== attributed {
            coordinator.text = attributed
            coordinator.measured.removeAll()
            uiView.attributedText = attributed
        }
        if let size = coordinator.measured[maxWidth] { return size }
        let bounds = attributed.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let fitted = uiView.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        let size = CGSize(width: min(maxWidth, ceil(bounds.width) + 1), height: ceil(fitted.height))
        if coordinator.measured.count > 8 { coordinator.measured.removeAll() }
        coordinator.measured[maxWidth] = size
        return size
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onQuote: ((String) -> Void)?
        var text: NSAttributedString?
        var measured: [CGFloat: CGSize] = [:]

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let onQuote, range.length > 0, let text = textView.text, let swiftRange = Range(range, in: text) else {
                return UIMenu(children: suggestedActions)
            }
            let excerpt = String(text[swiftRange])
            let quote = UIAction(title: "Quote", image: UIImage(systemName: "text.quote")) { _ in
                onQuote(excerpt)
                textView.selectedTextRange = nil
            }
            return UIMenu(children: [quote] + suggestedActions)
        }
    }

    // MARK: - Rendering

    private static func colorKey(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.3f,%.3f,%.3f,%.3f", r, g, b, a)
    }

    private static func baseAttributes(font: UIFont, color: UIColor, lineSpacing: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    }

    static func render(markdown: String, font: UIFont, color: UIColor, lineSpacing: CGFloat, codeBackground: UIColor) -> NSAttributedString {
        let base = baseAttributes(font: font, color: color, lineSpacing: lineSpacing)
        guard let parsed = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return NSAttributedString(string: markdown, attributes: base)
        }
        let out = NSMutableAttributedString()
        for run in parsed.runs {
            var attrs = base
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) {
                attrs[.font] = UIFont.monospacedSystemFont(ofSize: font.pointSize - 2, weight: .regular)
                attrs[.backgroundColor] = codeBackground
            } else {
                var traits: UIFontDescriptor.SymbolicTraits = []
                if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
                if intent.contains(.emphasized) { traits.insert(.traitItalic) }
                if !traits.isEmpty, let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                    attrs[.font] = UIFont(descriptor: descriptor, size: font.pointSize)
                }
            }
            if intent.contains(.strikethrough) {
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let link = run.link {
                attrs[.link] = link
            }
            out.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attrs))
        }
        return out
    }
}
