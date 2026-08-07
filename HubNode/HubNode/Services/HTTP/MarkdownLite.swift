import Foundation

// MARK: - Lightweight markdown → HTML for Kea web bubbles
/// Server-side so the console does not depend on fragile client hydration.
/// Supports: paragraphs, headings, numbered/bullet lists, **bold**, *italic*, `code`.
///
/// Models often return JSON-escaped newlines as the two characters `\` + `n`
/// (especially when the whole payload is double-encoded). We normalize those
/// before splitting lines so "1. … 2. …" does not render as one jammed line.
///
/// IMPORTANT: never treat the second `*` of `**bold**` as a list bullet. A prior
/// force-break regex did that and produced `**Heavy Rain Warning` / `*` on the next line.

enum MarkdownLite {
 static func toHTML(_ src: String) -> String {
  let raw = normalizeLineBreaks(src)
  let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  var out: [String] = []
  var buf: [String] = []

  func flush() {
   guard !buf.isEmpty else { return }
   out.append("<p>" + buf.joined(separator: "<br>") + "</p>")
   buf.removeAll()
  }

  for line in lines {
   let trimmed = line.trimmingCharacters(in: .whitespaces)
   if trimmed.isEmpty {
    flush()
    continue
   }
   if let m = trimmed.prefixMatch(of: /^(#{1,3})\s+(.*)$/) {
    flush()
    let hashes = String(m.1)
    let body = String(m.2)
    let tag = hashes.count == 1 ? "h2" : "h3"
    out.append("<\(tag)>\(inline(body))</\(tag)>")
    continue
   }
   // Whole-line bold used as a section title: **Note:** / **Immediate Actions**
   if let m = trimmed.prefixMatch(of: /^\*\*(.+?)\*\*:?\s*$/) {
    flush()
    out.append("<h3>\(inline(String(m.1)))</h3>")
    continue
   }
   if let m = trimmed.prefixMatch(of: /^(\d+)[\.)]\s+(.*)$/) {
    flush()
    // Real space after "2." so even if CSS grid fails we never render "2.text"
    out.append(
     #"<div class="md-li"><span class="n">\#(escape(String(m.1))).</span> <span class="md-li-body">\#(inline(String(m.2)))</span></div>"#
    )
    continue
   }
   if let m = trimmed.prefixMatch(of: /^[-*•]\s+(.*)$/) {
    flush()
    out.append(
     #"<div class="md-li"><span class="n">•</span> <span class="md-li-body">\#(inline(String(m.1)))</span></div>"#
    )
    continue
   }
   buf.append(inline(trimmed))
  }
  flush()
  return out.isEmpty ? "<p></p>" : out.joined()
 }

 /// Public so AskService can normalize plain-text answers too (Mac UI).
 static func normalizeLineBreaks(_ src: String) -> String {
  var raw = src
   .replacingOccurrences(of: "\r\n", with: "\n")
   .replacingOccurrences(of: "\r", with: "\n")
   .replacingOccurrences(of: "\u{2028}", with: "\n")
   .replacingOccurrences(of: "\u{2029}", with: "\n")

  // Literal backslash-n / backslash-t from double-encoded model JSON
  // Repeat a few times in case of "\\\\n"
  for _ in 0..<3 {
   if raw.contains("\\n") {
    raw = raw.replacingOccurrences(of: "\\n", with: "\n")
   }
   if raw.contains("\\t") {
    raw = raw.replacingOccurrences(of: "\\t", with: "\t")
   }
  }

  // If the whole answer is still a JSON object string, pull out "answer"
  if let extracted = extractJSONAnswer(raw) {
   raw = extracted
   for _ in 0..<3 {
    raw = raw.replacingOccurrences(of: "\\n", with: "\n")
   }
  }

  // Repair bold broken by an older force-break that split closing "**"
  // into "*\n*". Join those first, then close any still-unbalanced line
  // whose next line is only residual "*" / "**".
  for _ in 0..<3 {
   raw = raw.replacingOccurrences(
    of: #"\*\s*\n\s*\*(?!\*)"#,
    with: "**",
    options: .regularExpression
   )
  }
  raw = repairUnbalancedBoldLines(raw)

  // Force a line break before numbered steps when jammed onto previous text.
  // Require that the digit is not part of a time/decimal: look for start or non-word before.
  raw = raw.replacingOccurrences(
   of: #"(?<=[^\n\d])(?=\d{1,2}[\.)]\s)"#,
   with: "\n",
   options: .regularExpression
  )

  // Force break before real list bullets (• or -). Do NOT use bare "*" here:
  // it matches the second asterisk of "**bold**" whenever bold is followed by
  // whitespace/content and produces "\n*" orphans (the "Heavy Rain Warning / *" bug).
  raw = raw.replacingOccurrences(
   of: #"([^\n])(?=[•]\s+\S)"#,
   with: "$1\n",
   options: .regularExpression
  )
  // Hyphen bullets only when clearly a list marker (" - item" / ". - item"), not "well-known"
  raw = raw.replacingOccurrences(
   of: #"([^\n\w])(?=-\s+\S)"#,
   with: "$1\n",
   options: .regularExpression
  )
  // Asterisk bullets: single "*" not part of "**", and followed by space + text
  raw = raw.replacingOccurrences(
   of: #"([^\n*])(?=\*\s+\S)"#,
   with: "$1\n",
   options: .regularExpression
  )

  return raw
 }

 private static func extractJSONAnswer(_ raw: String) -> String? {
  let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
  guard t.hasPrefix("{"), t.contains("\"answer\"") else { return nil }
  guard let data = t.data(using: .utf8),
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let answer = obj["answer"] as? String,
        !answer.isEmpty
  else { return nil }
  return answer
 }

 /// If a line has an odd number of `**` (unclosed bold) and the next line is
 /// only residual markers from a bad split, pull the closer onto this line.
 private static func repairUnbalancedBoldLines(_ raw: String) -> String {
  let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  guard !lines.isEmpty else { return raw }
  var out: [String] = []
  var i = 0
  while i < lines.count {
   let line = lines[i]
   if i + 1 < lines.count {
    let next = lines[i + 1].trimmingCharacters(in: .whitespaces)
    let boldMarks = line.components(separatedBy: "**").count - 1
    let nextIsOrphan = next == "*" || next == "**" || next.range(of: #"^\*+$"#, options: .regularExpression) != nil
    if boldMarks % 2 == 1 && nextIsOrphan {
     out.append(line.trimmingCharacters(in: .whitespacesAndNewlines) + "**")
     i += 2
     continue
    }
   }
   out.append(line)
   i += 1
  }
  return out.joined(separator: "\n")
 }

 private static func inline(_ s: String) -> String {
  var t = escape(s)
  t = t.replacingOccurrences(of: #"`([^`]+)`"#, with: "<code>$1</code>", options: .regularExpression)
  // Non-greedy bold so "**A** and **B**" both work; allow internal punctuation
  t = t.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
  t = t.replacingOccurrences(of: #"__(.+?)__"#, with: "<strong>$1</strong>", options: .regularExpression)
  t = t.replacingOccurrences(
   of: #"(^|[^*])\*([^*\n]+?)\*(?!\*)"#,
   with: "$1<em>$2</em>",
   options: .regularExpression
  )
  return t
 }

 private static func escape(_ s: String) -> String {
  s
   .replacingOccurrences(of: "&", with: "&amp;")
   .replacingOccurrences(of: "<", with: "&lt;")
   .replacingOccurrences(of: ">", with: "&gt;")
   .replacingOccurrences(of: "\"", with: "&quot;")
 }
}
