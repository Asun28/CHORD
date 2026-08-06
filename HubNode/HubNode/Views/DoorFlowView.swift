import SwiftUI
import SwiftData

struct DoorFlowView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let hub: Hub

    @State private var step = 0
    @State private var firstName = ""
    @State private var lastName = ""
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

    private var displayName: String {
        [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

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
            Text("First and last name go on the roster (and later the HTML board).")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("First name").font(.caption).foregroundStyle(.secondary)
                    TextField("First", text: $firstName)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last name").font(.caption).foregroundStyle(.secondary)
                    TextField("Last", text: $lastName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Button("Continue") { step = 1 }
                .buttonStyle(.borderedProminent)
                .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var quizStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A few questions")
                .font(.title2.weight(.semibold))
            Text("Assigning **\(displayName)**. Priority roles fill first from WREMO’s eight roles only.")
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
            // Lanyard-style card for web/print mental model
            VStack(alignment: .leading, spacing: 8) {
                Text("TEAM ROSTER CARD")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                if let a = resultAssignment {
                    Text("\(a.firstName.isEmpty ? displayName : a.firstName) \(a.lastName)".trimmingCharacters(in: .whitespaces))
                        .font(.title.weight(.bold))
                    if let suggestion {
                        Text(roleName(suggestion.roleCode))
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                        Text(suggestion.rationale)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if let second = suggestion.secondChoice {
                            Text("Second choice: \(roleName(second))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text("Role code: \(a.roleCode)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
            }

            Text("Your first tasks")
                .font(.headline)
            ForEach(resultTasks, id: \.templateID) { t in
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.text)
                    Text(t.sourceRef)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            Button("Done — back to board") { dismiss() }
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
                "name": displayName,
            ]
            let (assignment, tasks, sug) = try await app.doorFlow.assignWalkIn(
                session: session,
                firstName: firstName,
                lastName: lastName,
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
