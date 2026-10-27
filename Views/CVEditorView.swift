import SwiftUI

struct CVEditorView: View {
    @State var decisions: CVDecisions
    let pools: CVBulletPools
    /// Current LaTeX of the CV being edited; the job titles are read from its headings
    let latex: String
    let jd: String
    let jobId: Int
    let profile: String
    var onRebuild: (String, Data, CVDecisions) -> Void

    @State private var isRebuilding = false
    @State private var rebuildError: String?
    @State private var swapTarget: SwapTarget?
    @State private var showSkillsPicker = false
    @State private var showSummarySkillsPicker = false
    @State private var showJD = false
    @State private var livePools: CVBulletPools? = nil
    // Per-CV degree phrase in the summary — shorten it here so the summary fits on one page
    @State private var summaryDegree: String = ""
    @State private var defaultSummaryDegree: String = ""
    // Per-CV job titles, one per work-experience heading in the LaTeX. Sent on every rebuild so an
    // earlier edit survives later bullet or skills changes.
    @State private var jobTitles: [JobTitleEdit] = []
    @Environment(\.dismiss) private var dismiss

    private var activePools: CVBulletPools { livePools ?? pools }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                skillsSection
                projectSection
                if !jobTitles.isEmpty { jobTitlesSection }
                ForEach(CVCompany.cases(for: profile), id: \.self) { companySection($0) }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit CV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showJD = true
                    } label: {
                        Label("JD", systemImage: "doc.text")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 13, weight: .medium))
                    }
                }
            }
            .sheet(isPresented: $showJD) {
                JDQuickView(jd: jd)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
            .safeAreaInset(edge: .bottom) { rebuildBar }
            .onAppear { if jobTitles.isEmpty { jobTitles = JobTitleEdit.parse(latex: latex) } }
            .task { await refreshPools() }
            .sheet(item: $swapTarget) { target in
                BulletPickerView(target: target, decisions: $decisions, pools: activePools)
            }
            .sheet(isPresented: $showSkillsPicker) {
                SkillsPickerView(
                    title: "Skills Line",
                    subtitle: "These appear in the Skills section of your CV",
                    allSkills: activePools.skillsArray,
                    initialSelected: decisions.skillsLine
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty },
                    onDone: { ordered in
                        decisions.skillsLine = ordered.joined(separator: ", ")
                    }
                )
            }
            .sheet(isPresented: $showSummarySkillsPicker) {
                SkillsPickerView(
                    title: "Summary Skills",
                    subtitle: "Skills highlighted in your professional summary",
                    allSkills: activePools.skillsArray,
                    initialSelected: decisions.skills,
                    onDone: { ordered in
                        decisions.skills = ordered
                    }
                )
            }
        }
    }

    // MARK: - Summary section

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Role").font(.caption).foregroundColor(.secondary)
                TextField("e.g. React Native Engineer", text: $decisions.role)
                    .font(.system(size: 14))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Focus Area (optional)").font(.caption).foregroundColor(.secondary)
                TextField("e.g. mobile performance", text: Binding(
                    get: { decisions.focusArea ?? "" },
                    set: { decisions.focusArea = $0.isEmpty ? nil : $0 }
                ))
                .font(.system(size: 14))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Degree (in summary)").font(.caption).foregroundColor(.secondary)
                TextField(defaultSummaryDegree.isEmpty ? "e.g. MSc in Adv. Software Engineering" : defaultSummaryDegree,
                          text: $summaryDegree)
                    .font(.system(size: 14))
                    .autocorrectionDisabled()
                if !summaryDegree.isEmpty && summaryDegree != defaultSummaryDegree {
                    Button {
                        Task {
                            var settings = (try? await CVProfileService.fetchProfile(for: profile))?.settings ?? .empty
                            settings.summaryDegree = summaryDegree
                            try? await CVProfileService.saveSettings(settings, for: profile)
                            defaultSummaryDegree = summaryDegree
                        }
                    } label: {
                        Label("Save as default for future CVs", systemImage: "square.and.arrow.down")
                            .font(.caption)
                            .foregroundColor(.indigo)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Summary Skills")
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                    Text(decisions.skills.isEmpty ? "None selected" : decisions.skills.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.secondary).font(.caption)
            }
            .contentShape(Rectangle())
            .onTapGesture { showSummarySkillsPicker = true }
        } header: {
            Text("Professional Summary")
        }
    }

    // MARK: - Skills section

    private var skillsSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Skills Line")
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                    Text(decisions.skillsLine.isEmpty ? "None selected" : decisions.skillsLine)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.secondary).font(.caption)
            }
            .contentShape(Rectangle())
            .onTapGesture { showSkillsPicker = true }
        } header: {
            Text("Skills")
        }
    }

    // MARK: - Project section

    private var projectSection: some View {
        Section("Project") {
            ForEach(activePools.projectOptions) { option in
                HStack {
                    Text(option.title)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if decisions.projectKey == option.key {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.indigo)
                    } else {
                        Image(systemName: "circle").foregroundColor(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { decisions.projectKey = option.key }
            }
        }
    }

    // MARK: - Job titles section

    private var jobTitlesSection: some View {
        Section {
            ForEach($jobTitles) { $item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.company).font(.caption).foregroundColor(.secondary)
                    TextField(item.original, text: $item.title)
                        .font(.system(size: 14))
                        .autocorrectionDisabled()
                }
            }
        } header: {
            Text("Job Titles")
        } footer: {
            Text("Applies to this CV only. Edit the template in CV Profile to change a title for every CV.")
        }
    }

    // MARK: - Work experience section builder

    @ViewBuilder
    private func companySection(_ company: CVCompany) -> some View {
        let selected = company.selectedIndices(in: decisions)
        let pool = activePools.pool(for: company)
        Section(company.displayName(for: profile)) {
            ForEach(Array(selected.enumerated()), id: \.element) { _, idx in
                if let entry = pool.first(where: { $0.index == idx }) {
                    BulletRowView(entry: entry) {
                        swapTarget = SwapTarget(company: company, bulletIndex: idx)
                    }
                }
            }
            .onMove { from, to in
                switch company {
                case .nHabit: decisions.nHabitBullets.move(fromOffsets: from, toOffset: to)
                case .campConnection: decisions.campBullets.move(fromOffsets: from, toOffset: to)
                case .projexino: decisions.projexinoBullets.move(fromOffsets: from, toOffset: to)
                case .samyak: decisions.samyakBullets.move(fromOffsets: from, toOffset: to)
                }
            }
        }
    }

    // MARK: - Rebuild bar

    private var rebuildBar: some View {
        VStack(spacing: 6) {
            if let err = rebuildError {
                Text(err).font(.caption).foregroundColor(.red).multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button {
                Task { await rebuild() }
            } label: {
                Group {
                    if isRebuilding {
                        HStack(spacing: 8) {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Rebuilding PDF…")
                        }
                    } else {
                        Label("Rebuild PDF", systemImage: "arrow.clockwise")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.indigo)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isRebuilding)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Refresh pools from server

    private func refreshPools() async {
        guard let freshProfile = try? await CVProfileService.fetchProfile(for: profile) else { return }
        func convert(_ bullets: [CVProfileBullet]) -> [CVBulletEntry] {
            bullets.enumerated().map { i, b in
                CVBulletEntry(index: i + 1, displayText: b.displayText, pinned: b.pinned, skills: b.skills)
            }
        }
        livePools = CVBulletPools(
            nHabit: convert(freshProfile.bullets.nHabit),
            campConnection: convert(freshProfile.bullets.campConnection),
            projexino: convert(freshProfile.bullets.projexino),
            samyak: convert(freshProfile.bullets.samyak),
            skillsArray: freshProfile.skills,
            projectOptions: pools.projectOptions
        )
        let stored = freshProfile.settings?.summaryDegree ?? ""
        defaultSummaryDegree = stored
        if summaryDegree.isEmpty { summaryDegree = stored }
    }

    // MARK: - Rebuild action

    private func rebuild() async {
        isRebuilding = true
        rebuildError = nil
        do {
            let override = summaryDegree.trimmingCharacters(in: .whitespaces)
            let titleOverrides = jobTitles
                .map { JobTitleOverride(company: $0.company, title: $0.title.trimmingCharacters(in: .whitespaces)) }
                .filter { !$0.title.isEmpty }
            let (latex, pdfData) = try await CVService.rebuild(
                decisions: decisions, jd: jd, profile: profile,
                summaryDegree: override.isEmpty || override == defaultSummaryDegree ? nil : override,
                jobTitles: titleOverrides.isEmpty ? nil : titleOverrides
            )
            let updated = CVResult(latex: latex, pdfData: pdfData, decisions: decisions, pools: pools)
            CVCacheStore.save(updated, for: jobId)
            onRebuild(latex, pdfData, decisions)
            dismiss()
        } catch {
            rebuildError = error.localizedDescription
        }
        isRebuilding = false
    }
}

// MARK: - Job title edit

/// A work-experience heading parsed from the CV's LaTeX. The company anchors the override on the
/// worker; the title is what the user edits.
struct JobTitleEdit: Identifiable {
    let id: Int
    let company: String
    let original: String
    var title: String

    /// Every \resumeSubheading{company}{location}{title}{dates} block in the document, in order.
    /// Education and project headings use longer macro names and are skipped by the lookahead.
    static func parse(latex: String) -> [JobTitleEdit] {
        let pattern = #/\\resumeSubheading(?![A-Za-z])\s*\{([^{}]*)\}\s*\{[^{}]*\}\s*\{([^{}]*)\}\s*\{[^{}]*\}/#
        return latex.matches(of: pattern).enumerated().map { i, match in
            let company = unescape(String(match.1))
            let title = unescape(String(match.2))
            return JobTitleEdit(id: i, company: company, original: title, title: title)
        }
    }

    /// "Kith \& Kids" → "Kith & Kids"; the worker re-escapes whatever goes back
    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: #"\\([&%#_$])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Bullet row

private struct BulletRowView: View {
    let entry: CVBulletEntry
    let onSwap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.displayText)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            if !entry.pinned {
                Label("Replace", systemImage: "arrow.left.arrow.right")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.indigo)
                    .onTapGesture { onSwap() }
            } else {
                Label("Pinned", systemImage: "pin.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Swap target

struct SwapTarget: Identifiable {
    let company: CVCompany
    let bulletIndex: Int
    var id: String { "\(company.rawValue)-\(bulletIndex)" }
}

// MARK: - Skills picker sheet

struct SkillsPickerView: View {
    let title: String
    let subtitle: String
    let allSkills: [String]
    let initialSelected: [String]
    var onDone: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var localSelected: [String] = []
    @State private var newSkill: String = ""

    private var available: [String] {
        allSkills.filter { !localSelected.contains($0) }
    }

    /// Adds a tag that is not in the pool (e.g. "Amplitude" for one bullet). A case-insensitive match
    /// against the pool or the current selection reuses the existing spelling instead of duplicating it.
    private func addNewSkill() {
        let typed = newSkill.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        let existing = (localSelected + allSkills).first { $0.caseInsensitiveCompare(typed) == .orderedSame }
        let skill = existing ?? typed
        if !localSelected.contains(skill) { localSelected.append(skill) }
        newSkill = ""
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.indigo)
                        TextField("Add a skill not in the list…", text: $newSkill)
                            .font(.system(size: 14))
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit { addNewSkill() }
                        if !newSkill.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button("Add") { addNewSkill() }
                                .buttonStyle(.borderless)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.indigo)
                        }
                    }
                }
                if !localSelected.isEmpty {
                    Section {
                        ForEach(localSelected, id: \.self) { skill in
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.indigo)
                                Text(skill)
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "xmark.circle")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 14))
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { localSelected.removeAll { $0 == skill } }
                        }
                        .onMove { localSelected.move(fromOffsets: $0, toOffset: $1) }
                    } header: {
                        Text("Selected — tap to remove, drag to reorder")
                    }
                }
                Section("Available") {
                    ForEach(available, id: \.self) { skill in
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle")
                                .foregroundColor(.secondary)
                            Text(skill)
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !localSelected.contains(skill) else { return }
                            localSelected.append(skill)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDone(localSelected)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .onAppear { localSelected = initialSelected }
    }
}

// MARK: - Bullet picker sheet

struct BulletPickerView: View {
    let target: SwapTarget
    @Binding var decisions: CVDecisions
    let pools: CVBulletPools
    @Environment(\.dismiss) private var dismiss

    private var pool: [CVBulletEntry] { pools.pool(for: target.company) }
    private var currentIndices: Set<Int> { Set(target.company.selectedIndices(in: decisions)) }

    var body: some View {
        NavigationStack {
            List(pool) { entry in
                let isCurrent = entry.index == target.bulletIndex
                let isSelected = currentIndices.contains(entry.index) && !isCurrent
                Button {
                    guard !isSelected else { return }
                    swap(to: entry.index)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            Text(entry.displayText)
                                .font(.system(size: 13))
                                .foregroundColor(isSelected ? .secondary : .primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            if isCurrent {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.indigo)
                            } else if isSelected {
                                Image(systemName: "minus.circle").foregroundColor(.secondary)
                            }
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(entry.skills.prefix(5), id: \.self) { skill in
                                    Text(skill)
                                        .font(.system(size: 10, weight: .medium))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.indigo.opacity(0.12))
                                        .foregroundColor(.indigo)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .disabled(isSelected)
            }
            .listStyle(.plain)
            .navigationTitle("Choose Replacement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func swap(to newIndex: Int) {
        switch target.company {
        case .nHabit:
            decisions.nHabitBullets = decisions.nHabitBullets.map { $0 == target.bulletIndex ? newIndex : $0 }
        case .campConnection:
            decisions.campBullets = decisions.campBullets.map { $0 == target.bulletIndex ? newIndex : $0 }
        case .projexino:
            decisions.projexinoBullets = decisions.projexinoBullets.map { $0 == target.bulletIndex ? newIndex : $0 }
        case .samyak:
            decisions.samyakBullets = decisions.samyakBullets.map { $0 == target.bulletIndex ? newIndex : $0 }
        }
    }
}
