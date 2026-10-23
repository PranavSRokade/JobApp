import SwiftUI

/// Everything you've applied to, grouped by stage. Independent of the loaded sheet — each entry
/// carries its own snapshot of the job.
struct ApplicationsView: View {
    @ObservedObject var store: ApplicationsStore
    @ObservedObject var starredStore: StarredJobsStore
    let profile: String
    @State private var showStages = false

    private var grouped: [(stage: ApplicationStage, apps: [Application])] {
        store.stages.compactMap { stage in
            let apps = store.applications.filter { $0.stageId == stage.id }.sorted { $0.appliedAt > $1.appliedAt }
            return apps.isEmpty ? nil : (stage, apps)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.applications.isEmpty {
                    ContentUnavailableView(
                        "No applications yet",
                        systemImage: "paperplane",
                        description: Text("Open a job and tap “Mark as applied”. Applications stay here whatever sheet is loaded.")
                    )
                } else {
                    List {
                        ForEach(grouped, id: \.stage.id) { group in
                            Section {
                                ForEach(group.apps) { app in
                                    NavigationLink {
                                        JobDetailView(
                                            job: app.job,
                                            sheetName: app.sheet,
                                            starredStore: starredStore,
                                            applicationsStore: store,
                                            profile: profile,
                                            region: app.region
                                        )
                                    } label: {
                                        ApplicationRow(app: app, store: store)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            store.unmark(app.id)
                                        } label: {
                                            Label("Remove", systemImage: "trash")
                                        }
                                    }
                                    .contextMenu { stageMenu(for: app) }
                                }
                            } header: {
                                Text("\(group.stage.name) · \(group.apps.count)")
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("\(store.applications.count) Applications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showStages = true } label: {
                        Label("Stages", systemImage: "list.bullet.indent")
                    }
                }
            }
            .refreshable { await store.refresh() }
            .sheet(isPresented: $showStages) {
                StagesEditorView(store: store)
            }
        }
    }

    @ViewBuilder
    private func stageMenu(for app: Application) -> some View {
        ForEach(store.stages) { stage in
            Button {
                store.setStage(app.id, stageId: stage.id)
            } label: {
                if stage.id == app.stageId {
                    Label(stage.name, systemImage: "checkmark")
                } else {
                    Text(stage.name)
                }
            }
        }
    }
}

private struct ApplicationRow: View {
    let app: Application
    @ObservedObject var store: ApplicationsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(app.job.title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(2)
            Text("\(app.job.company) · \(app.job.location)")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(app.appliedAgoText)
                    .font(.system(size: 12))
                    .foregroundColor(app.daysSinceApplied >= 14 ? .orange : .secondary)
                if let summary = app.applicantsSummary {
                    Text("·").font(.system(size: 12)).foregroundColor(.secondary)
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Menu {
                    ForEach(store.stages) { stage in
                        Button(stage.name) { store.setStage(app.id, stageId: stage.id) }
                    }
                } label: {
                    Text(store.stageName(app.stageId))
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.indigo.opacity(0.12))
                        .foregroundColor(.indigo)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Stages editor

private struct StagesEditorView: View {
    @ObservedObject var store: ApplicationsStore
    @Environment(\.dismiss) private var dismiss
    @State private var newStage = ""
    @State private var renaming: ApplicationStage? = nil
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New stage…", text: $newStage)
                            .autocorrectionDisabled()
                        Button {
                            store.addStage(named: newStage)
                            newStage = ""
                        } label: {
                            Image(systemName: "plus.circle.fill").foregroundColor(.indigo)
                        }
                        .buttonStyle(.plain)
                        .disabled(newStage.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section {
                    ForEach(store.stages) { stage in
                        HStack {
                            Text(stage.name).font(.system(size: 14))
                            Spacer()
                            Text("\(store.count(in: stage.id))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            renaming = stage
                            renameText = stage.name
                        }
                        .contextMenu {
                            Button {
                                renaming = stage
                                renameText = stage.name
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                        }
                    }
                    .onMove { store.moveStages(from: $0, to: $1) }
                    .onDelete { offsets in
                        let ids = offsets.map { store.stages[$0].id }
                        ids.forEach { store.deleteStage($0) }
                    }
                } header: {
                    Text("Stages — tap to rename, drag to reorder, swipe to delete")
                } footer: {
                    Text("Deleting a stage moves its applications to the first stage. New applications start in the first stage.")
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Stages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename stage", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    if let stage = renaming { store.renameStage(stage.id, to: renameText) }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
        }
    }
}
