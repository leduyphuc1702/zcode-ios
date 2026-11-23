import SwiftUI
import UIKit

/// Message text with native range selection (long-press a word, drag the handles), like selecting text
/// in the desktop transcript. The edit menu adds "Quote" next to Copy, matching the desktop selection toolbar.
struct SelectableMessageText: UIViewRepresentable {
    let attributed: NSAttributedString
    var onQuote: ((String) -> Void)?

    init(markdown: String, font: UIFont, color: UIColor, lineSpacing: CGFloat, codeBackground: UIColor, linkColor: UIColor, onQuote: ((String) -> Void)? = nil) {
        self.attributed = Self.render(markdown: markdown, font: font, color: color, lineSpacing: lineSpacing, codeBackground: codeBackground)
        self.linkColor = linkColor
        self.onQuote = onQuote
    }

    init(plain: String, font: UIFont, color: UIColor, lineSpacing: CGFloat, linkColor: UIColor, onQuote: ((String) -> Void)? = nil) {
        self.attributed = NSAttributedString(string: plain, attributes: Self.baseAttributes(font: font, color: color, lineSpacing: lineSpacing))
        self.linkColor = linkColor
        self.onQuote = onQuote
    }

    private let linkColor: UIColor

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
        if tv.attributedText != attributed {
            tv.attributedText = attributed
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let maxWidth = proposal.width ?? UIScreen.main.bounds.width
        guard maxWidth > 0, maxWidth.isFinite else { return nil }
        let bounds = attributed.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let fitted = uiView.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        return CGSize(width: min(maxWidth, ceil(bounds.width) + 1), height: ceil(fitted.height))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onQuote: ((String) -> Void)?

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
