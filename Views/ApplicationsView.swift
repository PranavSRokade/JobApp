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

// MARK: - Progress

/// What happened to every application, in four views: where they all are now, how they flow from
/// one stage to the next, how each week's batch turned out, and how long the unanswered ones have
/// waited compared with how fast replies actually come. Then your shortlist guesses against results.
private struct StageStatsView: View {
    @ObservedObject var store: ApplicationsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let summary = ProgressSummary(store: store)
        NavigationStack {
            List {
                Section {
                    OutcomeBar(summary: summary)
                } header: {
                    Text("Where they are now")
                }
                Section {
                    FlowView(summary: summary)
                } header: {
                    Text("How far they got")
                } footer: {
                    Text("Every application starts on the left. The ribbon that carries on is the ones that reached the next stage.")
                }
                Section {
                    WeeklyChart(summary: summary)
                } header: {
                    Text("By week applied")
                } footer: {
                    Text("Each bar is the applications you sent that week, coloured by how they've turned out so far.")
                }
                Section {
                    WaitingView(summary: summary)
                } header: {
                    Text("How long you've waited")
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
}

/// Where an application stands now. Progressing means it reached any stage after the first.
private enum Outcome: String, CaseIterable, Plottable {
    case waiting = "No reply", rejected = "Rejected", progressing = "In progress", withdrawn = "Withdrawn"

    var color: Color {
        switch self {
        case .waiting: return Color(.systemGray3)
        case .rejected: return .red
        case .progressing: return .green
        case .withdrawn: return Color(.systemGray)
        }
    }
}

/// Everything the four views need, worked out once from the store
private struct ProgressSummary {
    struct Week: Identifiable { let start: Date; let outcome: Outcome; let count: Int; var id: String { "\(start)-\(outcome.rawValue)" } }
    struct Step: Identifiable { let name: String; let count: Int; var id: String { name } }

    let total: Int
    let counts: [Outcome: Int]
    /// The first stage's split: how many stopped there and how, and how many went on
    let stoppedWaiting: Int, stoppedRejected: Int, stoppedWithdrawn: Int, wentOn: Int
    /// Stages after the first that anyone reached, with how many reached each
    let laterSteps: [Step]
    let firstStageName: String
    let weeks: [Week]
    let waitingDays: [Int]
    let replyDays: [Int]

    init(store: ApplicationsStore, now: Date = Date()) {
        let progress = store.stages.filter { !store.isTerminal($0.id) }
        let index = Dictionary(uniqueKeysWithValues: progress.enumerated().map { ($1.id, $0) })
        func furthest(_ app: Application) -> Int { store.furthestStage(app).flatMap { index[$0.id] } ?? 0 }
        func withdrawn(_ app: Application) -> Bool {
            app.stageId == "withdrawn" || store.stageName(app.stageId).lowercased().hasPrefix("withdr")
        }
        func outcome(_ app: Application) -> Outcome {
            if store.isTerminal(app.stageId) { return withdrawn(app) ? .withdrawn : .rejected }
            return furthest(app) >= 1 ? .progressing : .waiting
        }

        let apps = store.applications
        total = apps.count
        counts = Dictionary(grouping: apps, by: outcome).mapValues(\.count)
        let stopped = apps.filter { furthest($0) == 0 }
        stoppedWaiting = stopped.filter { outcome($0) == .waiting }.count
        stoppedRejected = stopped.filter { outcome($0) == .rejected }.count
        stoppedWithdrawn = stopped.filter { outcome($0) == .withdrawn }.count
        wentOn = apps.count - stopped.count
        firstStageName = progress.first?.name ?? "Applied"
        laterSteps = progress.enumerated().dropFirst().compactMap { i, stage in
            let n = apps.filter { furthest($0) >= i }.count
            return n > 0 ? Step(name: stage.name, count: n) : nil
        }

        let cal = Calendar(identifier: .iso8601)
        let byWeek = Dictionary(grouping: apps) { cal.dateInterval(of: .weekOfYear, for: $0.appliedAt)?.start ?? $0.appliedAt }
        weeks = byWeek.keys.sorted().suffix(10).flatMap { start in
            Outcome.allCases.compactMap { o in
                let n = byWeek[start]!.filter { outcome($0) == o }.count
                return n > 0 ? Week(start: start, outcome: o, count: n) : nil
            }
        }

        waitingDays = apps.filter { outcome($0) == .waiting }.map(\.daysSinceApplied)
        // Time from applying to the first change of stage, whatever it was: that's when they replied
        replyDays = apps.compactMap { app in
            guard app.history.count > 1 else { return nil }
            return Calendar.current.dateComponents([.day], from: app.history[0].at, to: app.history[1].at).day
        }
    }

    func count(_ o: Outcome) -> Int { counts[o] ?? 0 }
}

// MARK: 1. Where they are now

private struct OutcomeBar: View {
    let summary: ProgressSummary

    var body: some View {
        let shown = Outcome.allCases.filter { summary.count($0) > 0 }
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(shown, id: \.self) { o in
                        Rectangle().fill(o.color)
                            .frame(width: max(4, (geo.size.width - CGFloat(shown.count - 1) * 2) * CGFloat(summary.count(o)) / CGFloat(max(summary.total, 1))))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: 22)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 6) {
                ForEach(shown, id: \.self) { o in
                    HStack(spacing: 6) {
                        Circle().fill(o.color).frame(width: 9, height: 9)
                        Text("\(summary.count(o))").font(.subheadline.weight(.semibold)).monospacedDigit()
                        Text(o.rawValue.lowercased()).font(.subheadline).foregroundColor(.secondary)
                        Text(share(o)).font(.caption).foregroundColor(.secondary).monospacedDigit()
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func share(_ o: Outcome) -> String {
        (Double(summary.count(o)) / Double(max(summary.total, 1))).formatted(.percent.precision(.fractionLength(0)))
    }
}

// MARK: 2. Flow

/// A small Sankey: the first stage splits into "went on", no reply, rejected and withdrawn; the
/// went-on ribbon then narrows through each later stage anyone reached. Went-on sits on top so its
/// chain has a clear lane, and every column is labelled in the band above the ribbons.
private struct FlowView: View {
    let summary: ProgressSummary

    private struct Node { let label: String; let count: Int; let color: Color }

    var body: some View {
        let wentOn = Node(label: summary.laterSteps.first?.name ?? "Went on", count: summary.wentOn, color: Outcome.progressing.color)
        let splits = [
            wentOn,
            Node(label: "No reply", count: summary.stoppedWaiting, color: Outcome.waiting.color),
            Node(label: "Rejected", count: summary.stoppedRejected, color: Outcome.rejected.color),
            Node(label: "Withdrawn", count: summary.stoppedWithdrawn, color: Outcome.withdrawn.color),
        ].filter { $0.count > 0 }
        let chain = Array(summary.laterSteps.dropFirst())
        Canvas { ctx, size in
            guard summary.total > 0 else { return }
            let top: CGFloat = 34, gap: CGFloat = 8
            let usable = size.height - top - gap * CGFloat(max(splits.count - 1, 0))
            let unit = usable / CGFloat(summary.total)
            let h = { (n: Int) in max(3, CGFloat(n) * unit) }
            let barW: CGFloat = 10
            let x0: CGFloat = 0, x1 = size.width * 0.42
            let leftH = h(summary.total)
            ctx.fill(Path(roundedRect: CGRect(x: x0, y: top, width: barW, height: leftH), cornerRadius: 3), with: .color(.indigo))
            let chainStep = chain.isEmpty ? 0 : (size.width - x1 - 90) / CGFloat(chain.count)
            // column labels share the band above the ribbons, each wrapping inside its own column
            func label(_ text: String, x: CGFloat, width: CGFloat, bold: Bool = false) {
                ctx.draw(Text(text).font(bold ? .caption2.weight(.semibold) : .caption2), in: CGRect(x: x, y: 0, width: width, height: top - 4))
            }
            label("\(summary.firstStageName) \(summary.total)", x: x0, width: x1 - x0 - 6, bold: true)
            var leftY = top, rightY = top
            var wentOnRect: CGRect?
            for node in splits {
                let nh = h(node.count)
                ctx.fill(ribbon(from: CGRect(x: x0 + barW, y: leftY, width: 0, height: nh),
                                to: CGRect(x: x1, y: rightY, width: 0, height: nh)), with: .color(node.color.opacity(0.45)))
                let r = CGRect(x: x1, y: rightY, width: barW, height: nh)
                ctx.fill(Path(r), with: .color(node.color))
                if node.label == wentOn.label && node.color == wentOn.color {
                    wentOnRect = r
                    label("\(node.label) \(node.count)", x: x1, width: chain.isEmpty ? size.width - x1 : chainStep - 6)
                } else {
                    ctx.draw(Text("\(node.label) \(node.count)").font(.caption2), at: CGPoint(x: x1 + barW + 4, y: r.midY), anchor: .leading)
                }
                leftY += nh
                rightY += nh + gap
            }
            // the ones that went on, narrowing through each later stage
            guard var from = wentOnRect, !chain.isEmpty else { return }
            for (i, s) in chain.enumerated() {
                let x = x1 + chainStep * CGFloat(i + 1)
                let to = CGRect(x: x, y: from.minY, width: barW, height: h(s.count))
                ctx.fill(ribbon(from: CGRect(x: from.maxX, y: from.minY, width: 0, height: to.height),
                                to: CGRect(x: to.minX, y: to.minY, width: 0, height: to.height)), with: .color(Outcome.progressing.color.opacity(0.45)))
                ctx.fill(Path(to), with: .color(Outcome.progressing.color))
                label("\(s.name) \(s.count)", x: to.minX, width: i == chain.count - 1 ? size.width - to.minX : chainStep - 6)
                from = to
            }
        }
        .frame(height: 200)
        .padding(.vertical, 6)
        .accessibilityLabel(accessibilityText(splits.map { "\($0.label) \($0.count)" }))
    }

    private func ribbon(from a: CGRect, to b: CGRect) -> Path {
        var p = Path()
        let mid = (a.minX + b.minX) / 2
        p.move(to: CGPoint(x: a.minX, y: a.minY))
        p.addCurve(to: CGPoint(x: b.minX, y: b.minY), control1: CGPoint(x: mid, y: a.minY), control2: CGPoint(x: mid, y: b.minY))
        p.addLine(to: CGPoint(x: b.minX, y: b.maxY))
        p.addCurve(to: CGPoint(x: a.minX, y: a.maxY), control1: CGPoint(x: mid, y: b.maxY), control2: CGPoint(x: mid, y: a.maxY))
        p.closeSubpath()
        return p
    }

    private func accessibilityText(_ parts: [String]) -> String {
        "\(summary.firstStageName) \(summary.total), then " + (parts + summary.laterSteps.dropFirst().map { "\($0.name) \($0.count)" }).joined(separator: ", ")
    }
}

// MARK: 3. By week applied

private struct WeeklyChart: View {
    let summary: ProgressSummary

    var body: some View {
        Chart(summary.weeks) { w in
            BarMark(x: .value("Week", w.start, unit: .weekOfYear), y: .value("Applications", w.count))
                .foregroundStyle(by: .value("Outcome", w.outcome))
        }
        .chartForegroundStyleScale(domain: Outcome.allCases, range: Outcome.allCases.map(\.color))
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
            }
        }
        .chartLegend(position: .bottom, spacing: 8)
        .frame(height: 200)
        .padding(.vertical, 6)
    }
}

// MARK: 4. How long you've waited

/// The unanswered ones by days since applying, against how quickly replies have actually come.
/// Anything older than your slowest reply so far is very likely a silent no.
private struct WaitingView: View {
    let summary: ProgressSummary

    private struct Bucket: Identifiable { let label: String; let range: ClosedRange<Int>; let count: Int; var id: String { label } }

    var body: some View {
        let days = summary.waitingDays
        let buckets = [("0–7 days", 0...7), ("8–14", 8...14), ("15–21", 15...21), ("22+", 22...Int.max)]
            .map { Bucket(label: $0.0, range: $0.1, count: days.filter($0.1.contains).count) }
        let most = max(buckets.map(\.count).max() ?? 1, 1)
        let slowest = summary.replyDays.max()
        let typical = median(summary.replyDays)
        VStack(alignment: .leading, spacing: 8) {
            if days.isEmpty {
                Text("Nothing waiting for a reply.").font(.footnote).foregroundColor(.secondary)
            } else {
                ForEach(buckets) { b in
                    HStack(spacing: 8) {
                        Text(b.label).font(.subheadline).frame(width: 70, alignment: .leading)
                        GeometryReader { geo in
                            Capsule().fill(color(b, slowest: slowest))
                                .frame(width: b.count == 0 ? 0 : max(6, geo.size.width * CGFloat(b.count) / CGFloat(most)))
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 12)
                        Text("\(b.count)").font(.subheadline.weight(.semibold)).monospacedDigit().frame(width: 28, alignment: .trailing)
                    }
                }
                if let slowest, let typical {
                    let silent = days.filter { $0 > slowest }.count
                    Text("Replies came in \(typical) \(typical == 1 ? "day" : "days") typically, all within \(slowest). \(silent) of these \(silent == 1 ? "is" : "are") older than that, so probably silent no's.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 6)
    }

    /// Green while every reply so far would still fit, orange for the bucket your slowest reply falls
    /// in, grey once past it
    private func color(_ b: Bucket, slowest: Int?) -> Color {
        guard let slowest else { return Outcome.waiting.color }
        if b.range.upperBound <= slowest { return .green }
        if b.range.lowerBound <= slowest { return .orange }
        return Outcome.waiting.color
    }

    private func median(_ xs: [Int]) -> Int? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        return s[s.count / 2]
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
