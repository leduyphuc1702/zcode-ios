import SwiftUI
import UIKit

/// Native text selection sheet allowing users to select any excerpt of a chat message
/// and quote it directly into the composer.
struct MessageTextSelectionSheet: View {
    let text: String
    let senderName: String
    let onQuote: (String) -> Void
    let onCopy: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.zcodePalette) private var palette
    @State private var selectedExcerpt: String = ""

    private var effectiveExcerpt: String {
        let trimmed = selectedExcerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
    }

    private var hasPartialSelection: Bool {
        !selectedExcerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SelectableMessageTextView(
                    text: text,
                    textColor: UIColor(palette.foreground),
                    tintColor: UIColor(palette.accentBlue),
                    selectedText: $selectedExcerpt
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .background(palette.background)

                Rectangle()
                    .fill(palette.border)
                    .frame(height: 1)

                HStack(spacing: 10) {
                    Text(hasPartialSelection ? "\(selectedExcerpt.count) chars selected" : "Drag to select part of the message")
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.foregroundMuted)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Button {
                        onCopy(effectiveExcerpt)
                        dismiss()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(palette.foreground)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(palette.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(palette.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("copySelectedMessageTextButton")

                    Button {
                        guard !effectiveExcerpt.isEmpty else { return }
                        onQuote(effectiveExcerpt)
                        dismiss()
                    } label: {
                        Label(hasPartialSelection ? "Quote selection" : "Quote all", systemImage: "text.quote")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(palette.brandForeground)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(palette.brand, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(effectiveExcerpt.isEmpty)
                    .accessibilityIdentifier("quoteSelectedMessageTextButton")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(palette.header)
            }
            .background(palette.background)
            .navigationTitle("Select text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(palette.foregroundSubtle)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct SelectableMessageTextView: UIViewRepresentable {
    let text: String
    let textColor: UIColor
    let tintColor: UIColor
    @Binding var selectedText: String

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedText: $selectedText)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = true
        tv.backgroundColor = .clear
        tv.font = UIFont.systemFont(ofSize: 15.5)
        tv.textColor = textColor
        tv.tintColor = tintColor
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 0, bottom: 20, right: 0)
        tv.textContainer.lineFragmentPadding = 0
        tv.dataDetectorTypes = []
        tv.delegate = context.coordinator
        tv.text = text
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.textColor = textColor
        uiView.tintColor = tintColor
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var selectedText: String

        init(selectedText: Binding<String>) {
            _selectedText = selectedText
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let range = textView.selectedRange
            guard range.length > 0,
                  let swiftRange = Range(range, in: textView.text ?? "") else {
                if !selectedText.isEmpty {
                    DispatchQueue.main.async {
                        self.selectedText = ""
                    }
                }
                return
            }
            let excerpt = String((textView.text ?? "")[swiftRange])
            if excerpt != selectedText {
                DispatchQueue.main.async {
                    self.selectedText = excerpt
                }
            }
        }
    }
}
