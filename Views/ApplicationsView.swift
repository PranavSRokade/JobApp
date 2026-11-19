import SwiftUI
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
    @State private var showAdd = false

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
                    Button { showAdd = true } label: {
                        Label("Add application", systemImage: "plus")
                    }
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
            .sheet(isPresented: $showAdd) {
                AddApplicationView(store: store, profile: profile)
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

    // Short on purpose: with nine stages listed inline, the CV items ended up below the fold
    @ViewBuilder
    private func appMenu(for app: Application) -> some View {
        Menu {
            stageMenu(for: app)
        } label: {
            Label("Move to stage", systemImage: "arrow.right.circle")
        }
        Button { historyJobId = app.id } label: {
            Label("Edit history…", systemImage: "clock.arrow.circlepath")
        }
        Divider()
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
            Text(app.job.location.isEmpty ? app.job.company : "\(app.job.company) · \(app.job.location)")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(app.appliedAgoText)
                    .font(.system(size: 12))
                    .foregroundColor(app.daysSinceApplied >= 14 ? .orange : .secondary)
                if let chance = app.shortlistChance {
                    Text("\(chance)/10")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundColor(ShortlistChance.color(chance))
                        .accessibilityLabel("Shortlist guess \(chance) out of 10")
                }
                if app.isCustom {
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Added by hand")
                }
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

// MARK: - Progress funnel

/// How far applications get: each stage counts every application that reached at least that far,
/// with the share of all applications and how many were rejected there. Stages nobody has reached
/// collapse into one line. Plain rows rather than a chart, so the names sit beside their numbers.
private struct StageStatsView: View {
    @ObservedObject var store: ApplicationsStore
    @Environment(\.dismiss) private var dismiss

    private struct Row: Identifiable {
        let stage: ApplicationStage
        let reached: Int
        let endedHere: Int
        var id: String { stage.id }
    }

    private var progressStages: [ApplicationStage] { store.stages.filter { !store.isTerminal($0.id) } }

    private var rows: [Row] {
        let order = Dictionary(uniqueKeysWithValues: progressStages.enumerated().map { ($1.id, $0) })
        let furthest = store.applications.map { app in (app, store.furthestStage(app).flatMap { order[$0.id] } ?? 0) }
        return progressStages.enumerated().map { i, stage in
            Row(
                stage: stage,
                reached: furthest.filter { $0.1 >= i }.count,
                endedHere: furthest.filter { $0.1 == i && store.isTerminal($0.0.stageId) }.count
            )
        }
    }

    private var total: Int { store.applications.count }
    private var ended: Int { store.applications.filter { store.isTerminal($0.stageId) }.count }

    var body: some View {
        let all = rows
        let reached = all.filter { $0.reached > 0 }
        let notYet = all.filter { $0.reached == 0 }.map(\.stage.name)
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 0) {
                        stat("\(total)", "applied")
                        stat("\(total - ended)", "waiting")
                        stat("\(ended)", "ended")
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    ForEach(reached) { row in
                        FunnelRow(name: row.stage.name, reached: row.reached, total: max(total, 1), endedHere: row.endedHere)
                    }
                    if !notYet.isEmpty {
                        Text("Not reached yet: \(notYet.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("How far applications get")
                } footer: {
                    Text("Each stage counts every application that got at least that far. A wrong step can be removed with Edit history.")
                }
                GuessesSection(store: store)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Done") { dismiss() } }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(label).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FunnelRow: View {
    let name: String
    let reached: Int
    let total: Int
    let endedHere: Int

    private var share: Double { Double(reached) / Double(total) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(reached)").font(.system(size: 15, weight: .semibold)).monospacedDigit()
                Text(share.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(Color.indigo).frame(width: max(6, geo.size.width * share))
                }
            }
            .frame(height: 8)
            if endedHere > 0 {
                Text("\(endedHere) rejected or withdrawn at this stage")
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.85))
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
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

// MARK: - Shortlist guess

/// "How likely is a shortlist?" asked right after applying, 0–10. A light tick on every step while
/// sliding and a firmer one at either end, so it can be set by feel. The guesses feed Progress.
struct ShortlistChanceSheet: View {
    let title: String
    let company: String
    let onSave: (Int) -> Void
    @State private var value: Double
    @Environment(\.dismiss) private var dismiss
    private let ticks = UISelectionFeedbackGenerator()
    private let ends = UIImpactFeedbackGenerator(style: .medium)

    init(title: String, company: String, initial: Int?, onSave: @escaping (Int) -> Void) {
        self.title = title
        self.company = company
        self.onSave = onSave
        _value = State(initialValue: Double(initial ?? 5))
    }

    private var chance: Int { Int(value.rounded()) }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text("Chance of a shortlist?").font(.headline)
                Text("\(title) · \(company)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(chance)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .contentTransition(.numericText(value: value))
                    Text("/10").font(.title3.weight(.semibold)).foregroundColor(.secondary)
                }
                .foregroundColor(ShortlistChance.color(chance))
                Text(ShortlistChance.label(chance))
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
            }
            .animation(.snappy(duration: 0.15), value: chance)
            VStack(spacing: 6) {
                Slider(value: $value, in: 0...10, step: 1)
                    .tint(ShortlistChance.color(chance))
                HStack {
                    ForEach(0...10, id: \.self) { n in
                        Text("\(n)")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(n == chance ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .onChange(of: chance) { _, new in
                if new == 0 || new == 10 { ends.impactOccurred() } else { ticks.selectionChanged() }
            }
            HStack(spacing: 12) {
                Button("Skip") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Button {
                    onSave(chance)
                    dismiss()
                } label: {
                    Text("Save").fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.indigo)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(20)
        .onAppear { ticks.prepare(); ends.prepare() }
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.visible)
    }
}

enum ShortlistChance {
    static func label(_ n: Int) -> String {
        switch n {
        case ...2: return "Long shot"
        case 3...4: return "Unlikely"
        case 5...6: return "Decent"
        case 7...8: return "Strong"
        default: return "Very likely"
        }
    }

    static func color(_ n: Int) -> Color {
        switch n {
        case ...3: return .red
        case 4...6: return .orange
        default: return .green
        }
    }
}

// MARK: - Add an application by hand

/// A job applied to outside the scraped sheets (a company site, a referral, an email). Optionally
/// makes a quick CV from the pasted description and attaches it as the CV sent, then asks for the
/// shortlist guess like any other application.
struct AddApplicationView: View {
    @ObservedObject var store: ApplicationsStore
    let profile: String
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var company = ""
    @State private var link = ""
    @State private var location = ""
    @State private var jd = ""
    @State private var makeCV = true
    @State private var saving = false
    @State private var error: String?
    @State private var added: Job?

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasJD: Bool { !trimmed(jd).isEmpty }
    private var canSave: Bool { !trimmed(title).isEmpty && !trimmed(company).isEmpty && !saving && added == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Job") {
                    TextField("Role", text: $title)
                    TextField("Company", text: $company)
                    TextField("Link (optional)", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Location (optional)", text: $location)
                }
                Section {
                    TextEditor(text: $jd).frame(minHeight: 160)
                    Toggle("Make a quick CV and attach it", isOn: $makeCV).disabled(!hasJD)
                } header: {
                    Text("Job description")
                } footer: {
                    Text(hasJD ? "The CV is built from this description and saved as the CV you sent. Open it from the application."
                               : "Paste the description to make a quick CV. You can also attach your own PDF later.")
                }
                if let error {
                    Section { Text(error).font(.footnote).foregroundColor(.red) }
                }
            }
            .navigationTitle("Add application")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Save", action: save).fontWeight(.semibold).disabled(!canSave)
                    }
                }
            }
            .interactiveDismissDisabled(saving)
            .sheet(item: $added, onDismiss: { dismiss() }) { job in
                ShortlistChanceSheet(title: job.title, company: job.company, initial: nil) {
                    store.setShortlistChance(job.jobId, $0)
                }
            }
        }
    }

    private func save() {
        let job = store.addCustom(
            title: trimmed(title), company: trimmed(company), link: trimmed(link),
            location: trimmed(location), jd: hasJD ? trimmed(jd) : nil
        )
        guard makeCV && hasJD else { added = job; return }
        saving = true
        Task {
            do {
                let result = try await CVService.generateCV(jd: trimmed(jd), profile: profile)
                let name = resumeFileName(title: job.title, company: job.company, location: job.location.isEmpty ? nil : job.location)
                try await store.attachCV(job.jobId, data: result.pdfData, name: name.hasSuffix(".pdf") ? name : "\(name).pdf")
            } catch {
                // The application is saved either way; only the CV is missing
                self.error = "Saved, but the CV failed: \(error.localizedDescription)"
                saving = false
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            saving = false
            added = job
        }
    }
}

// MARK: - Shortlist guesses vs what happened

/// Your 0–10 guesses grouped into three bands, each with how many were actually shortlisted
/// (reached any stage after the first). Shows whether your gut is calibrated, and so which kinds
/// of applications deserve the extra effort.
private struct GuessesSection: View {
    @ObservedObject var store: ApplicationsStore

    struct Band: Identifiable {
        let name: String
        let range: ClosedRange<Int>
        var total = 0
        var shortlisted = 0
        var waiting = 0
        var id: String { name }
    }

    private func shortlisted(_ app: Application) -> Bool {
        let progress = store.stages.filter { !store.isTerminal($0.id) }
        guard let furthest = store.furthestStage(app), let i = progress.firstIndex(where: { $0.id == furthest.id }) else { return false }
        return i >= 1
    }

    private var guessed: [Application] { store.applications.filter { $0.shortlistChance != nil } }

    private var bands: [Band] {
        var out = [Band(name: "0–3 long shots", range: 0...3), Band(name: "4–6 decent", range: 4...6), Band(name: "7–10 strong", range: 7...10)]
        for app in guessed {
            guard let c = app.shortlistChance, let i = out.firstIndex(where: { $0.range.contains(c) }) else { continue }
            out[i].total += 1
            if shortlisted(app) { out[i].shortlisted += 1 } else if !store.isTerminal(app.stageId) { out[i].waiting += 1 }
        }
        return out
    }

    var body: some View {
        let apps = guessed
        Section {
            if apps.isEmpty {
                Text("No guesses yet. After you mark a job applied, rate your chance of a shortlist out of 10.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                let avg = Double(apps.compactMap(\.shortlistChance).reduce(0, +)) / Double(apps.count)
                let hits = apps.filter(shortlisted).count
                let decided = apps.filter { shortlisted($0) || store.isTerminal($0.stageId) }.count
                HStack(spacing: 0) {
                    stat(avg.formatted(.number.precision(.fractionLength(1))), "average guess")
                    stat(decided == 0 ? "–" : (Double(hits) / Double(decided)).formatted(.percent.precision(.fractionLength(0))), "shortlisted")
                    stat("\(apps.count - decided)", "waiting")
                }
                .padding(.vertical, 4)
                ForEach(bands.filter { $0.total > 0 }) { band in
                    GuessBandRow(band: band)
                }
            }
        } header: {
            Text("Your shortlist guesses")
        } footer: {
            Text("Shortlisted means it reached any stage after the first. The rate counts only applications with an answer, so a band full of waiting ones says little yet. An average guess of 6 should mean about 60% shortlisted.")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(label).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct GuessBandRow: View {
    let band: GuessesSection.Band

    private var decided: Int { band.total - band.waiting }
    private var rate: Double { decided == 0 ? 0 : Double(band.shortlisted) / Double(decided) }
    private var color: Color { ShortlistChance.color(band.range.upperBound) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(band.name).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(band.shortlisted) of \(band.total) shortlisted")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(color).frame(width: max(6, geo.size.width * rate))
                }
            }
            .frame(height: 8)
            if band.waiting > 0 {
                Text("\(band.waiting) still waiting")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
