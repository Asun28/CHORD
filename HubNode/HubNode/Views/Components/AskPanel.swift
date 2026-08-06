import SwiftUI
import SwiftData

/// Ask panel on the hub board — `answer_question` (architecture.md §6).
/// Deliberately plain: question in, cited answer out, unknowns on the face of it.
struct AskPanel: View {
    @EnvironmentObject private var app: AppModel
    let hub: Hub
    var posture: Posture = .green
    var drivers: [SituationDriver] = []

    @State private var question: String = ""
    @State private var result: AskResultVO?
    @State private var isAsking = false
    @State private var showPassages = false

    private static let examples = [
        "Do we need to open the hub tonight?",
        "How do I set up?",
        "Where's the water tank?",
        "What does Reception do?",
        "Who are our neighbouring hubs?",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            askField
            exampleRow

            if isAsking {
                ProgressView()
                    .controlSize(.small)
            }
            if let result {
                answerCard(result)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Sub-views

    private var header: some View {
        HStack(spacing: 8) {
            Label("Ask", systemImage: "text.bubble")
                .font(.headline)
            Spacer()
            if app.inferenceClient.isRemoteConfigured {
                Label(NodeConfig.shared.modelName, systemImage: "brain")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .help("Local model endpoint is configured")
            } else {
                Label("Corpus only", systemImage: "books.vertical")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(app.viewLevel.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(app.viewLevel == .coordinator ? .orange : .secondary)
        }
    }

    private var askField: some View {
        HStack(spacing: 8) {
            TextField("Ask about this hub…", text: $question)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submit() }
            Button("Ask") { submit() }
                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || isAsking)
        }
    }

    private var exampleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Self.examples, id: \.self) { example in
                    Button {
                        question = example
                        submit()
                    } label: {
                        Text(example)
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private func answerCard(_ result: AskResultVO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(result.intent.title)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
                Spacer()
                if let reviewed = result.planReviewedOn {
                    Text("plan reviewed \(reviewed) · \(result.planCurrency.rawValue)")
                        .font(.caption2)
                        .foregroundStyle(result.planCurrency == .stale ? Color.orange : Color.secondary)
                } else {
                    Text("no published plan")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Label(result.modeLabel, systemImage: result.isDegraded ? "wifi.slash" : "sparkles")
                .font(.caption)
                .foregroundStyle(result.isDegraded ? .orange : .secondary)

            MarkdownText(source: result.answer, font: .body)

            if !result.unknowns.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(result.unknowns, id: \.self) { unknown in
                        Label(unknown, systemImage: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !result.citations.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sources")
                        .font(.caption.weight(.semibold))
                    ForEach(result.citations) { citation in
                        Text("\(citation.kind.label): \(citation.label)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !result.passages.isEmpty {
                DisclosureGroup(isExpanded: $showPassages) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(result.passages) { passage in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(passage.citation.label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(passage.text)
                                    .font(.caption)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Text("Retrieved passages (\(result.passages.count)) — verbatim")
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(result.isDegraded ? Color.orange.opacity(0.07) : Color.secondary.opacity(0.05))
        )
    }

    // MARK: - Actions

    private func submit() {
        let asked = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty, !isAsking else { return }
        isAsking = true
        Task {
            let answered = await app.ask(question: asked, hub: hub)
            result = answered
            // A cold model means the passages *are* the answer — open them.
            showPassages = answered.isDegraded
            isAsking = false
        }
    }
}
