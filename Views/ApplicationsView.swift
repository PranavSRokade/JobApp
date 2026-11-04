import SwiftUI
import Charts
import QuickLook
import UniformTypeIdentifiers

/// Everything you've applied to, grouped by stage. Independent of the loaded sheet — each entry
/// carries its own snapshot of the job.
struct ApplicationsView: View {
    @ObservedObject var store: ApplicationsStore
    @ObservedObject var starredStore: StarredJobsStore
    let profile: String
    @State private var showStages = false
    @State private var showStats = false
    @State private var searchText = ""
    @State private var historyJobId: Int? = nil
    @State private var importerJobId: Int? = nil
    @State private var showImporter = false
    @State private var previewURL: URL? = nil
    @State private var cvBusy = false
    @State private var cvError: String? = nil

    private var query: String { searchText.trimmingCharacters(in: .whitespaces) }

    /// Company and title only, so a search for "london" doesn't match half the list by location
    private func matches(_ app: Application) -> Bool {
        query.isEmpty || app.job.company.localizedCaseInsensitiveContains(query) || app.job.title.localizedCaseInsensitiveContains(query)
    }

    private var grouped: [(stage: ApplicationStage, apps: [Application])] {
        store.stages.compactMap { stage in
            let apps = store.applications.filter { $0.stageId == stage.id && matches($0) }.sorted { $0.appliedAt > $1.appliedAt }
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
                } else if grouped.isEmpty {
                    ContentUnavailableView.search(text: query)
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
                                    .contextMenu { appMenu(for: app) }
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
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Company or role")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if cvBusy { ProgressView() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showStats = true } label: {
                        Label("Progress", systemImage: "chart.bar.xaxis")
                    }
                    .disabled(store.applications.isEmpty)
                    Button { showStages = true } label: {
                        Label("Stages", systemImage: "list.bullet.indent")
                    }
                }
            }
            .refreshable { await store.refresh() }
            .sheet(isPresented: $showStages) {
                StagesEditorView(store: store)
            }
            .sheet(isPresented: $showStats) {
                StageStatsView(store: store)
            }
            .sheet(item: Binding(get: { historyJobId.map(IdentifiedJob.init) }, set: { historyJobId = $0?.id })) { item in
                HistoryEditorView(store: store, jobId: item.id)
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf]) { result in
                guard let jobId = importerJobId else { return }
                importerJobId = nil
                switch result {
                case .success(let url): runCV { try await store.attachCV(jobId, from: url) }
                case .failure(let error): cvError = error.localizedDescription
                }
            }
            .quickLookPreview($previewURL)
            .alert("CV", isPresented: Binding(get: { cvError != nil }, set: { if !$0 { cvError = nil } })) {
                Button("OK", role: .cancel) { cvError = nil }
            } message: {
                Text(cvError ?? "")
            }
        }
    }

    private func runCV(_ work: @escaping () async throws -> Void) {
        Task {
            cvBusy = true
            do { try await work() } catch { cvError = error.localizedDescription }
            cvBusy = false
        }
    }

    @ViewBuilder
    private func appMenu(for app: Application) -> some View {
        stageMenu(for: app)
        Divider()
        Button { historyJobId = app.id } label: {
            Label("Edit history…", systemImage: "clock.arrow.circlepath")
        }
        if app.customCV != nil {
            Button { runCV { previewURL = try await store.downloadCV(app.id) } } label: {
                Label("View CV", systemImage: "doc.text.magnifyingglass")
            }
        }
        Button {
            importerJobId = app.id
            showImporter = true
        } label: {
            Label(app.customCV == nil ? "Attach CV…" : "Replace CV…", systemImage: "doc.badge.plus")
        }
        if app.customCV != nil {
            Button(role: .destructive) { runCV { try await store.removeCV(app.id) } } label: {
                Label("Remove CV", systemImage: "doc.badge.ellipsis")
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
                if app.customCV != nil {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.indigo)
                        .accessibilityLabel("CV attached")
                }
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

private struct IdentifiedJob: Identifiable { let id: Int }

// MARK: - Progress chart

/// Each application counted once, at the furthest stage it reached, split by how it ended. Answers
/// "how far do I get before a rejection" without asking for any new data: it reads the history.
private struct StageStatsView: View {
    @ObservedObject var store: ApplicationsStore
    @Environment(\.dismiss) private var dismiss

    private struct Bar: Identifiable {
        let stage: String
        let outcome: String
        let count: Int
        var id: String { "\(stage)|\(outcome)" }
    }

    private var progressStages: [ApplicationStage] { store.stages.filter { !store.isTerminal($0.id) } }

    private func outcome(_ app: Application) -> String {
        store.isTerminal(app.stageId) ? store.stageName(app.stageId) : "Still active"
    }

    private var bars: [Bar] {
        var counts: [String: [String: Int]] = [:]
        for app in store.applications {
            guard let stage = store.furthestStage(app) else { continue }
            counts[stage.id, default: [:]][outcome(app), default: 0] += 1
        }
        return progressStages.flatMap { stage in
            (counts[stage.id] ?? [:]).sorted { $0.key < $1.key }.map { Bar(stage: stage.name, outcome: $0.key, count: $0.value) }
        }
    }

    private func total(_ stage: ApplicationStage) -> Int {
        store.applications.filter { store.furthestStage($0)?.id == stage.id }.count
    }

    private func ended(_ stage: ApplicationStage) -> Int {
        store.applications.filter { store.furthestStage($0)?.id == stage.id && store.isTerminal($0.stageId) }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Chart(bars) { bar in
                        BarMark(
                            x: .value("Applications", bar.count),
                            y: .value("Furthest stage", bar.stage)
                        )
                        .foregroundStyle(by: .value("Outcome", bar.outcome))
                    }
                    .chartYScale(domain: progressStages.map(\.name))
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                    .chartLegend(position: .bottom)
                    .frame(height: CGFloat(max(progressStages.count, 1)) * 34 + 50)
                    .padding(.vertical, 6)
                } footer: {
                    Text("Each application counts once, at the furthest stage it reached. A wrong step can be removed with Edit history on the Applied list.")
                }
                Section("By stage") {
                    ForEach(progressStages) { stage in
                        HStack {
                            Text(stage.name).font(.system(size: 14))
                            Spacer()
                            let n = total(stage), out = ended(stage)
                            Text(n == 0 ? "–" : out == 0 ? "\(n)" : "\(n) · \(out) ended here")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - History editor

private struct HistoryEditorView: View {
    @ObservedObject var store: ApplicationsStore
    let jobId: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let app = store.application(for: jobId) {
                    Section {
                        ForEach(Array(app.history.enumerated()), id: \.offset) { _, step in
                            HStack {
                                Text(store.stageName(step.stageId)).font(.system(size: 14))
                                Spacer()
                                Text(step.at.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .deleteDisabled(app.history.count <= 1)
                        }
                        .onDelete { offsets in
                            offsets.sorted(by: >).forEach { store.removeHistoryStep(jobId, at: $0) }
                        }
                    } header: {
                        Text("\(app.job.company) · \(app.job.title)")
                    } footer: {
                        Text("Swipe a step to delete it. The application moves to the stage that is then last.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Done") { dismiss() } }
            }
        }
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
