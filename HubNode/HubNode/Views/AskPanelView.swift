import SwiftUI

/// Corpus-grounded Q&A for the current hub (guide + CRP + structured facts + optional local model).
struct AskPanelView: View {
    @EnvironmentObject private var app: AppModel
    let hub: Hub

    @State private var question = ""
    @State private var result: AskResultVO?
    @State private var isAsking = false
    @State private var history: [AskResultVO] = []

    private let suggestions = [
        "Should we open the hub?",
        "Where is the emergency water tank?",
        "What are the priority roles?",
        "Who are our neighbouring hubs?",
        "How current is our response plan?",
        "What do we do when setting up?",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Ask the playbook", systemImage: "text.bubble")
                    .font(.headline)
                Spacer()
                if app.inferenceClient.isRemoteConfigured {
                    Label("Local model", systemImage: "brain")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    Label("Corpus only", systemImage: "books.vertical")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Answers use this hub’s plan, the regional Hub Guide, and live drivers. Restricted places stay gated.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Quick chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { s in
                        Button(s) {
                            question = s
                            Task { await runAsk() }
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                        .controlSize(.small)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Ask about this hub…", text: $question, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .onSubmit { Task { await runAsk() } }
                Button {
                    Task { await runAsk() }
                } label: {
                    if isAsking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Ask")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAsking || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let result {
                resultCard(result)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func resultCard(_ r: AskResultVO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(r.intent.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                Text(r.modeLabel)
                    .font(.caption2)
                    .foregroundStyle(r.isDegraded ? .orange : .secondary)
                Spacer()
            }

            MarkdownText(source: r.answer, font: .body)

            if !r.citations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sources")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(r.citations.prefix(8)) { c in
                        Text("• \(c.kind.label): \(c.label)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if !r.unknowns.isEmpty {
                Text("Unknowns: \(r.unknowns.joined(separator: "; "))")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }

    private func runAsk() async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isAsking = true
        defer { isAsking = false }
        let r = await app.ask(question: q, hub: hub)
        result = r
        history.insert(r, at: 0)
        if history.count > 20 { history = Array(history.prefix(20)) }
    }
}
