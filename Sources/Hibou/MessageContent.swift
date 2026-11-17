import AppKit
import SwiftUI

/// A reply split into prose and fenced code blocks (```lang … ```).
enum MessageSegment: Equatable {
    case text(String)
    case code(language: String, code: String)

    static func parse(_ text: String) -> [MessageSegment] {
        var segments: [MessageSegment] = []
        var prose: [Substring] = []
        var code: [Substring] = []
        var codeLanguage: String?

        func flushProse() {
            let joined = prose.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !joined.isEmpty { segments.append(.text(joined)) }
            prose = []
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let language = codeLanguage {
                    segments.append(.code(language: language, code: code.joined(separator: "\n")))
                    code = []
                    codeLanguage = nil
                } else {
                    flushProse()
                    codeLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
            } else if codeLanguage != nil {
                code.append(line)
            } else {
                prose.append(line)
            }
        }
        // A block still open (reply being streamed) is shown as code anyway.
        if let language = codeLanguage {
            segments.append(.code(language: language, code: code.joined(separator: "\n")))
        }
        flushProse()
        return segments
    }
}

/// Assistant reply: inline Markdown for prose, styled blocks for code.
struct AssistantMessageView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MessageSegment.parse(text).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let prose):
                    Text(markdown(prose))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .code(let codeLanguage, let code):
                    CodeBlockView(language: codeLanguage, code: code)
                }
            }
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var hovering = false
    @AppStorage(Language.storageKey) private var lang: Language = .fr

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                CopyButton(text: code, help: lang.t("Copier le code", "Copy code"))
                    .opacity(hovering ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
                    .padding(.bottom, 9)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.06)))
        .onHover { hovering = $0 }
    }
}

/// Small copy icon that turns into a checkmark for a moment once clicked.
struct CopyButton: View {
    let text: String
    let help: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11))
                .foregroundStyle(copied ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .frame(width: 18, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
