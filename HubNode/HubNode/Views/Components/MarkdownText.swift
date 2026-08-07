import SwiftUI

/// Renders model/guide markdown with **real line spacing**.
///
/// Apple's single `AttributedString(markdown:)` pass treats single newlines as
/// soft wraps, so numbered checklists collapse into one paragraph. We split on
/// lines / blank lines and parse **inline** markdown per block so bold works
/// and each step stays on its own line.
struct MarkdownText: View {
 let source: String
 var font: Font = .body
 /// Spacing between non-empty lines (checklist feel).
 var lineSpacing: CGFloat = 8
 /// Extra spacing for blank lines (paragraph breaks).
 var paragraphSpacing: CGFloat = 12

 var body: some View {
 VStack(alignment: .leading, spacing: 0) {
 ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
 switch block {
 case .blank:
 Color.clear
 .frame(height: paragraphSpacing)
 case .line(let text, let style):
 lineView(text, style: style)
 .padding(.bottom, lineSpacing)
 }
 }
 }
 .frame(maxWidth: .infinity, alignment: .leading)
 }

 @ViewBuilder
 private func lineView(_ text: String, style: LineStyle) -> some View {
 let attributed = Self.parseInline(text)
 switch style {
 case .heading:
 Text(attributed)
 .font(headingFont)
 .fontWeight(.semibold)
 .textSelection(.enabled)
 .fixedSize(horizontal: false, vertical: true)
 .padding(.top, 4)
 case .bullet:
 HStack(alignment: .top, spacing: 8) {
 Text("•")
 .font(font)
 Text(attributed)
 .font(font)
 .textSelection(.enabled)
 .fixedSize(horizontal: false, vertical: true)
 }
 case .numbered(let n):
 HStack(alignment: .top, spacing: 8) {
 Text("\(n).")
 .font(font.monospacedDigit())
 .fontWeight(.semibold)
 .frame(minWidth: 22, alignment: .trailing)
 Text(attributed)
 .font(font)
 .textSelection(.enabled)
 .fixedSize(horizontal: false, vertical: true)
 }
 case .body:
 Text(attributed)
 .font(font)
 .textSelection(.enabled)
 .fixedSize(horizontal: false, vertical: true)
 }
 }

 private var headingFont: Font {
 switch font {
 case .body, .callout: return .headline
 case .subheadline: return .subheadline.weight(.semibold)
 default: return font
 }
 }

 // MARK: - Block split

 private enum LineStyle {
 case body
 case heading
 case bullet
 case numbered(Int)
 }

 private enum Block {
 case blank
 case line(String, LineStyle)
 }

 private var blocks: [Block] {
 Self.split(source)
 }

 private static func split(_ raw: String) -> [Block] {
 // Same path as web: models often double-encode newlines as the two chars \ + n
 let normalized = MarkdownLite.normalizeLineBreaks(raw)
  .replacingOccurrences(of: "***", with: "**")

 let lines = normalized.components(separatedBy: "\n")
 var out: [Block] = []
 var previousBlank = false

 for line in lines {
 let trimmed = line.trimmingCharacters(in: .whitespaces)
 if trimmed.isEmpty {
 if !previousBlank && !out.isEmpty {
 out.append(.blank)
 previousBlank = true
 }
 continue
 }
 previousBlank = false
 out.append(.line(contentAndStyle(trimmed).0, contentAndStyle(trimmed).1))
 }
 // Drop trailing blank
 while case .blank = out.last {
 out.removeLast()
 }
 return out
 }

 private static func contentAndStyle(_ trimmed: String) -> (String, LineStyle) {
 // ## Heading / # Heading
 if let match = trimmed.range(of: #"^#{1,3}\s+"#, options: .regularExpression) {
 let rest = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespaces)
 return (rest, .heading)
 }
 // **Heading-like** full line bold only
 if trimmed.hasPrefix("**"), trimmed.hasSuffix("**"), trimmed.filter({ $0 == "*" }).count == 4,
 !trimmed.dropFirst(2).dropLast(2).contains("**") {
 let inner = String(trimmed.dropFirst(2).dropLast(2))
 return (inner, .heading)
 }
 // - item / * item (not **bold**)
 if trimmed.hasPrefix("- ") || (trimmed.hasPrefix("* ") && !trimmed.hasPrefix("**")) {
 let rest = String(trimmed.dropFirst(2))
 return (rest, .bullet)
 }
 // 1. item / 12. item
 if let match = trimmed.range(of: #"^(\d+)\.\s+"#, options: .regularExpression) {
 let numStr = trimmed[match].filter(\.isNumber)
 let n = Int(numStr) ?? 1
 let rest = String(trimmed[match.upperBound...])
 return (rest, .numbered(n))
 }
 // "1) item"
 if let match = trimmed.range(of: #"^(\d+)\)\s+"#, options: .regularExpression) {
 let numStr = trimmed[match].filter(\.isNumber)
 let n = Int(numStr) ?? 1
 let rest = String(trimmed[match.upperBound...])
 return (rest, .numbered(n))
 }
 return (trimmed, .body)
 }

 /// Inline markdown only (bold/italic/code). Newlines already handled by layout.
 static func parseInline(_ raw: String) -> AttributedString {
 var options = AttributedString.MarkdownParsingOptions()
 options.interpretedSyntax = .inlineOnlyPreservingWhitespace
 options.failurePolicy = .returnPartiallyParsedIfPossible
 if let rich = try? AttributedString(markdown: raw, options: options) {
 return rich
 }
 let stripped = raw
 .replacingOccurrences(of: "**", with: "")
 .replacingOccurrences(of: "__", with: "")
 .replacingOccurrences(of: "*", with: "")
 .replacingOccurrences(of: "`", with: "")
 return AttributedString(stripped)
 }
}
