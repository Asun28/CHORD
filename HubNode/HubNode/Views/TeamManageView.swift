import SwiftUI
import SwiftData

/// Coordinator / hall view of walk-ins: people, roles, task check-off, remove.
/// Mirrors the data a future HTML board will show (RosterExport).
struct TeamManageView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let hub: Hub
    let session: HubSession

    @Query(sort: \RoleDef.priorityRank) private var roles: [RoleDef]
    @State private var errorText: String?
    @State private var confirmRemove: Assignment?
    /// Force refresh after mutations (SwiftData relationships can lag UI).
    @State private var tick = 0

    private var assignments: [Assignment] {
        _ = tick
        return session.assignments.sorted { $0.assignedAt < $1.assignedAt }
    }

    private var tasks: [SessionTask] {
        _ = tick
        return session.tasks.sorted { lhs, rhs in
            if lhs.isDone != rhs.isDone { return !lhs.isDone && rhs.isDone }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private var openCount: Int { tasks.filter { !$0.isDone }.count }
    private var doneCount: Int { tasks.filter(\.isDone).count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Hub", value: hub.name)
                    LabeledContent("People", value: "\(assignments.count)")
                    LabeledContent("Tasks", value: "\(openCount) open · \(doneCount) done")
                    if app.coordinatorUnlocked {
                        Text("Coordinator mode on — full roster controls.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Tip: Unlock with kit code to see restricted facilities on the main board. Roster manage works either way in the hall.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("People") {
                    if assignments.isEmpty {
                        Text("No walk-ins yet. Use Walk-in on the board to add someone.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(assignments.enumerated()), id: \.offset) { _, person in
                            personRow(person)
                        }
                    }
                }

                Section("Tasks") {
                    if tasks.isEmpty {
                        Text("No tasks assigned yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(tasks.enumerated()), id: \.offset) { _, task in
                            taskRow(task)
                        }
                    }
                }

                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Manage team")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        // Re-open walk-in from parent via notification-like flag would be nicer;
                        // parent owns that sheet — dismiss so they can tap Walk-in.
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark.circle")
                    }
                }
            }
            .confirmationDialog(
                "Remove \(confirmRemove?.personName ?? "this person") from the roster?",
                isPresented: Binding(
                    get: { confirmRemove != nil },
                    set: { if !$0 { confirmRemove = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let person = confirmRemove {
                        remove(person)
                    }
                    confirmRemove = nil
                }
                Button("Cancel", role: .cancel) {
                    confirmRemove = nil
                }
            } message: {
                Text("Their open tasks will be cleared. Completed tasks stay on the session log.")
            }
        }
        .frame(minWidth: 520, minHeight: 560)
    }

    // MARK: - Rows

    @ViewBuilder
    private func personRow(_ person: Assignment) -> some View {
        let roleName = roles.first(where: { $0.code == person.roleCode })?.name ?? person.roleCode
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.personName)
                        .font(.headline)
                    Text("\(person.resolvedFirstName) · \(person.resolvedLastName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(roleName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(person.roleCode)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button(role: .destructive) {
                    confirmRemove = person
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Role reassignment
            Picker("Role", selection: Binding(
                get: { person.roleCode },
                set: { newCode in
                    changeRole(person, to: newCode)
                }
            )) {
                ForEach(roles, id: \.code) { role in
                    Text(role.isPriority ? "\(role.name) (P\(role.priorityRank))" : role.name)
                        .tag(role.code)
                }
            }
            .pickerStyle(.menu)

            let theirTasks = tasks.filter { $0.assigneeName == person.personName }
            if !theirTasks.isEmpty {
                Text("\(theirTasks.filter { !$0.isDone }.count) open · \(theirTasks.filter(\.isDone).count) done")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func taskRow(_ task: SessionTask) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                toggle(task)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.text)
                    .font(.subheadline)
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                HStack {
                    if let name = task.assigneeName {
                        Text(name).font(.caption.weight(.medium))
                    }
                    Text(task.roleCode)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(task.isDone ? "Done" : "Open")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(task.isDone ? .green : .orange)
                }
                Text(task.sourceRef)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func toggle(_ task: SessionTask) {
        do {
            try app.doorFlow.setTaskDone(task, done: !task.isDone)
            tick += 1
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func remove(_ person: Assignment) {
        do {
            try app.doorFlow.removePerson(person, from: session)
            tick += 1
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func changeRole(_ person: Assignment, to code: String) {
        do {
            try app.doorFlow.changeRole(person, to: code, session: session)
            // Keep their open tasks' role code in sync for export
            for t in session.tasks where t.assigneeName == person.personName && !t.isDone {
                t.roleCode = code
            }
            try modelContext.save()
            tick += 1
        } catch {
            errorText = error.localizedDescription
        }
    }
}
