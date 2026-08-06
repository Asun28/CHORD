import SwiftUI
import SwiftData

struct DoorFlowView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let hub: Hub

    @State private var step = 0
    @State private var name = ""
    @State private var q1 = ""
    @State private var q2 = ""
    @State private var q3 = ""
    @State private var resultAssignment: Assignment?
    @State private var resultTasks: [SessionTask] = []
    @State private var suggestion: RoleSuggestion?
    @State private var errorText: String?
    @State private var busy = false

    private let questions = [
        "What are you comfortable doing? (people, radio, organising, fixing…)",
        "Can you stay for the next few hours?",
        "Any skills we should know about? (first aid, languages, trades…)",
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                ProgressView(value: Double(step), total: 3)
                switch step {
                case 0: nameStep
                case 1: quizStep
                default: resultStep
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("Walk-in · \(hub.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Who just walked in?")
                .font(.title2.weight(.semibold))
            TextField("First name", text: $name)
                .textFieldStyle(.roundedBorder)
            Button("Continue") { step = 1 }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var quizStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A few questions")
                .font(.title2.weight(.semibold))
            Text("Priority roles fill first. The system picks from WREMO's eight roles only.")
                .font(.callout)
                .foregroundStyle(.secondary)

            labeledField(questions[0], text: $q1)
            labeledField(questions[1], text: $q2)
            labeledField(questions[2], text: $q3)

            if let errorText {
                Text(errorText).foregroundStyle(.red).font(.caption)
            }

            Button {
                Task { await assign() }
            } label: {
                if busy {
                    ProgressView()
                } else {
                    Text("Assign role & tasks")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy || q1.isEmpty)
        }
    }

    private var resultStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("You're on")
                .font(.title3)
                .foregroundStyle(.secondary)
            if let suggestion {
                Text(roleName(suggestion.roleCode))
                    .font(.largeTitle.weight(.bold))
                Text(suggestion.rationale)
                    .foregroundStyle(.secondary)
                if let second = suggestion.secondChoice {
                    Text("Second choice: \(roleName(second))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            if let a = resultAssignment {
                Text("Assigned to \(a.personName)")
                    .font(.headline)
            }

            Text("Your first tasks")
                .font(.headline)
                .padding(.top, 8)
            ForEach(resultTasks, id: \.templateID) { t in
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.text)
                    Text(t.sourceRef)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField("Answer", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func roleName(_ code: String) -> String {
        let d = FetchDescriptor<RoleDef>(predicate: #Predicate { $0.code == code })
        return (try? app.context.fetch(d).first)?.name ?? code
    }

    private func assign() async {
        busy = true
        defer { busy = false }
        do {
            let session = try app.doorFlow.openSession(hub: hub)
            let posture = app.posture(for: hub.id)
            let answers = [
                "q1": q1,
                "q2": q2,
                "q3": q3,
            ]
            let (assignment, tasks, sug) = try await app.doorFlow.assignWalkIn(
                session: session,
                personName: name,
                answers: answers,
                posture: posture
            )
            resultAssignment = assignment
            resultTasks = tasks
            suggestion = sug
            step = 2
        } catch {
            errorText = error.localizedDescription
        }
    }
}
