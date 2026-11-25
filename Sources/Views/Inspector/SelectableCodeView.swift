import SwiftUI
import UIKit

/// Read-only code canvas backed by one UITextView, so a selection can span any range of lines (long-press,
/// drag the handles, Copy) instead of copying a whole line at a time. Line numbers live in a gutter that
/// stays pinned while the code scrolls sideways; tapping a number, or "Comment" on a selection, starts an
/// inline code comment for those lines.
struct SelectableCodeView: UIViewRepresentable {
    let text: String
    let language: String
    let theme: ZCodeSyntaxTheme
    let fontSize: CGFloat
    let wrapLines: Bool
    var showLineNumbers: Bool = true
    var searchQuery: String = ""
    /// Called with 1-based start/end lines and the selected text.
    var onComment: ((Int, Int, String) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> CodeTextView {
        let view = CodeTextView()
        view.delegate = context.coordinator
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: CodeTextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onComment = onComment
        let colors = SyntaxColors.palette(for: theme)
        let style = CodeTextView.Style(
            fontSize: fontSize,
            wrapLines: wrapLines,
            showLineNumbers: showLineNumbers,
            showsCommentIcon: onComment != nil,
            background: UIColor(colors.background),
            gutterBackground: UIColor(colors.gutterBackground),
            gutterText: UIColor(colors.gutterText),
            tint: UIColor(colors.function)
        )
        view.apply(style: style, text: text)
        view.gutter.onTapLine = onComment.map { handler in
            { [weak view] line in handler(line, line, view?.lineText(line) ?? "") }
        }
        let key = "\(theme.rawValue)|\(fontSize)|\(language)|\(searchQuery)|\(text.hashValue)|\(text.utf16.count)"
        guard coordinator.highlightKey != key else { return }
        coordinator.highlightKey = key
        let palette = SyntaxHighlighter.DocumentPalette(colors: colors)
        let source = text, lang = language, size = fontSize, query = searchQuery
        // Small files highlight in place; large ones show plain text first so opening never blocks.
        if source.utf16.count <= 60_000 {
            view.setCode(SyntaxHighlighter.highlightDocument(source, language: lang, palette: palette, fontSize: size, searchQuery: query))
            return
        }
        view.setCode(SyntaxHighlighter.plainDocument(source, palette: palette, fontSize: size))
        DispatchQueue.global(qos: .userInitiated).async {
            let highlighted = SyntaxHighlighter.highlightDocument(source, language: lang, palette: palette, fontSize: size, searchQuery: query)
            DispatchQueue.main.async { [weak view] in
                guard let view, coordinator.highlightKey == key else { return }
                view.setCode(highlighted, preservingSelection: true)
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        weak var view: CodeTextView?
        var highlightKey = ""
        var onComment: ((Int, Int, String) -> Void)?

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let onComment, range.length > 0, let view else { return UIMenu(children: suggestedActions) }
            let nsText = textView.text as NSString
            let excerpt = nsText.substring(with: range)
            let start = view.lineNumber(atUTF16: range.location)
            let end = view.lineNumber(atUTF16: max(range.location, NSMaxRange(range) - 1))
            let comment = UIAction(title: "Comment", image: UIImage(systemName: "plus.bubble")) { _ in
                onComment(start, end, excerpt)
                textView.selectedTextRange = nil
            }
            return UIMenu(children: suggestedActions + [comment])
        }
    }
}

final class CodeTextView: UITextView {
    struct Style: Equatable {
        var fontSize: CGFloat
        var wrapLines: Bool
        var showLineNumbers: Bool
        var showsCommentIcon: Bool
        var background: UIColor
        var gutterBackground: UIColor
        var gutterText: UIColor
        var tint: UIColor
    }

    let gutter = CodeGutterView()
    private(set) var style: Style?
    /// UTF-16 offset where each line starts.
    private(set) var lineStarts: [Int] = [0]
    private var longestLineLength = 0
    private var gutterWidth: CGFloat = 0

    init() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        layout.allowsNonContiguousLayout = true
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        isEditable = false
        isSelectable = true
        alwaysBounceVertical = true
        autocorrectionType = .no
        smartQuotesType = .no
        dataDetectorTypes = []
        gutter.textView = self
        addSubview(gutter)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func apply(style newStyle: Style, text: String) {
        let lineCountChanged = recomputeLines(text)
        guard newStyle != style || lineCountChanged else { return }
        style = newStyle
        backgroundColor = newStyle.background
        tintColor = newStyle.tint
        gutter.backgroundColor = newStyle.gutterBackground
        indicatorStyle = .white

        let numberFont = gutter.numberFont(size: newStyle.fontSize)
        let digits = max(2, String(lineStarts.count).count)
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: numberFont]).width
        gutterWidth = newStyle.showLineNumbers ? ceil(CGFloat(digits) * digitWidth + (newStyle.showsCommentIcon ? 26 : 14)) : 0
        textContainerInset = UIEdgeInsets(top: 8, left: gutterWidth + 10, bottom: 8, right: 10)

        textContainer.widthTracksTextView = newStyle.wrapLines
        if !newStyle.wrapLines {
            let charWidth = ("M" as NSString).size(withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: newStyle.fontSize, weight: .semibold)]).width
            textContainer.size = CGSize(width: ceil(CGFloat(longestLineLength + 2) * charWidth), height: CGFloat.greatestFiniteMagnitude)
        }
        showsHorizontalScrollIndicator = !newStyle.wrapLines
        setNeedsLayout()
        gutter.setNeedsDisplay()
    }

    func setCode(_ attributed: NSAttributedString, preservingSelection: Bool = false) {
        let selection = selectedRange
        let offset = contentOffset
        attributedText = attributed
        if preservingSelection {
            if NSMaxRange(selection) <= attributed.length { selectedRange = selection }
            contentOffset = offset
        }
        gutter.setNeedsDisplay()
    }

    /// 1-based line containing the UTF-16 offset.
    func lineNumber(atUTF16 offset: Int) -> Int {
        var low = 0, high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low + 1
    }

    func lineText(_ line: Int) -> String {
        guard line >= 1, line <= lineStarts.count else { return "" }
        let ns = text as NSString
        let start = lineStarts[line - 1]
        let end = line < lineStarts.count ? lineStarts[line] - 1 : ns.length
        guard start <= end, end <= ns.length else { return "" }
        return ns.substring(with: NSRange(location: start, length: end - start))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let style, !style.wrapLines {
            let width = textContainer.size.width + textContainerInset.left + textContainerInset.right
            if abs(contentSize.width - width) > 0.5 { contentSize.width = width }
        }
        gutter.isHidden = gutterWidth == 0
        gutter.frame = CGRect(x: contentOffset.x, y: contentOffset.y, width: gutterWidth, height: bounds.height)
        bringSubviewToFront(gutter)
        gutter.setNeedsDisplay()
    }

    @discardableResult
    private func recomputeLines(_ text: String) -> Bool {
        var starts = [0]
        var longest = 0
        var offset = 0
        var current = 0
        for unit in text.utf16 {
            offset += 1
            if unit == 10 {
                starts.append(offset)
                longest = max(longest, current)
                current = 0
            } else {
                current += unit == 9 ? 4 : 1
            }
        }
        longest = max(longest, current)
        let changed = starts.count != lineStarts.count || longest != longestLineLength
        lineStarts = starts
        longestLineLength = longest
        return changed
    }
}

final class CodeGutterView: UIView {
    weak var textView: CodeTextView?
    var onTapLine: ((Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        contentMode = .redraw
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func numberFont(size: CGFloat) -> UIFont {
        .monospacedSystemFont(ofSize: max(8, size - 1), weight: .regular)
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard let textView, let onTapLine else { return }
        let y = recognizer.location(in: self).y + textView.contentOffset.y - textView.textContainerInset.top
        let layout = textView.layoutManager
        let glyph = layout.glyphIndex(for: CGPoint(x: 1, y: max(0, y)), in: textView.textContainer)
        let char = layout.characterIndexForGlyph(at: glyph)
        onTapLine(textView.lineNumber(atUTF16: min(char, (textView.text as NSString).length)))
    }

    override func draw(_ rect: CGRect) {
        guard let textView, let style = textView.style else { return }
        (backgroundColor ?? .clear).setFill()
        UIRectFill(rect)
        let font = numberFont(size: style.fontSize)
        let codeFont = UIFont.monospacedSystemFont(ofSize: style.fontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: style.gutterText]
        let icon = style.showsCommentIcon
            ? UIImage(systemName: "plus.bubble", withConfiguration: UIImage.SymbolConfiguration(pointSize: 9))?
                .withTintColor(style.gutterText.withAlphaComponent(0.6), renderingMode: .alwaysOriginal)
            : nil
        let numberRight = bounds.width - (icon == nil ? 8 : 20)
        let top = textView.textContainerInset.top - textView.contentOffset.y
        let baselineNudge = (codeFont.lineHeight - font.lineHeight) / 2

        func drawNumber(_ line: Int, fragmentTop: CGFloat) {
            let label = "\(line)" as NSString
            let size = label.size(withAttributes: attributes)
            let y = fragmentTop + top + baselineNudge
            label.draw(at: CGPoint(x: numberRight - size.width, y: y), withAttributes: attributes)
            if let icon {
                icon.draw(at: CGPoint(x: numberRight + 3, y: y + (size.height - icon.size.height) / 2))
            }
        }

        let layout = textView.layoutManager
        let container = textView.textContainer
        let visible = CGRect(x: 0, y: textView.contentOffset.y - textView.textContainerInset.top, width: container.size.width, height: bounds.height)
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let starts = textView.lineStarts
        layout.enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, glyphRange, _ in
            let char = layout.characterIndexForGlyph(at: glyphRange.location)
            let line = textView.lineNumber(atUTF16: char)
            guard starts[line - 1] == char else { return }
            drawNumber(line, fragmentTop: fragment.minY)
        }
        let extra = layout.extraLineFragmentRect
        if !extra.isEmpty, extra.maxY >= visible.minY, extra.minY <= visible.maxY {
            drawNumber(starts.count, fragmentTop: extra.minY)
        }
    }
}
