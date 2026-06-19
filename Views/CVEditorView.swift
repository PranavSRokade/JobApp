import SwiftUI

struct CVEditorView: View {
    @State var decisions: CVDecisions
    let pools: CVBulletPools
    let jd: String
    let jobId: Int
    var onRebuild: (String, Data) -> Void

    @State private var isRebuilding = false
    @State private var rebuildError: String?
    @State private var swapTarget: SwapTarget?
    @State private var showSkillsPicker = false
    @State private var showSummarySkillsPicker = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                summarySection
                skillsSection
                projectSection
                companySection(.nHabit)
                companySection(.campConnection)
                companySection(.projexino)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Edit CV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { rebuildBar }
            .sheet(item: $swapTarget) { target in
                BulletPickerView(target: target, decisions: $decisions, pools: pools)
            }
            .sheet(isPresented: $showSkillsPicker) {
                SkillsPickerView(
                    title: "Skills Line",
                    subtitle: "These appear in the Skills section of your CV",
                    allSkills: pools.skillsArray,
                    selected: Binding(
                        get: { Set(decisions.skillsLine.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }) },
                        set: { _ in }
                    ),
                    onDone: { selected in
                        decisions.skillsLine = pools.skillsArray.filter { selected.contains($0) }.joined(separator: ", ")
                    }
                )
            }
            .sheet(isPresented: $showSummarySkillsPicker) {
                SkillsPickerView(
                    title: "Summary Skills",
                    subtitle: "Skills highlighted in your professional summary",
                    allSkills: pools.skillsArray,
                    selected: Binding(
                        get: { Set(decisions.skills) },
                        set: { _ in }
                    ),
                    onDone: { selected in
                        decisions.skills = pools.skillsArray.filter { selected.contains($0) }
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
            Button {
                showSummarySkillsPicker = true
            } label: {
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
            }
        } header: {
            Text("Professional Summary")
        }
    }

    // MARK: - Skills section

    private var skillsSection: some View {
        Section {
            Button {
                showSkillsPicker = true
            } label: {
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
            }
        } header: {
            Text("Skills")
        }
    }

    // MARK: - Project section

    private var projectSection: some View {
        Section("Project") {
            ForEach(pools.projectOptions) { option in
                Button {
                    decisions.projectKey = option.key
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if decisions.projectKey == option.key {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.indigo)
                        } else {
                            Image(systemName: "circle").foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Work experience section builder

    @ViewBuilder
    private func companySection(_ company: CVCompany) -> some View {
        let selected = company.selectedIndices(in: decisions)
        let pool = pools.pool(for: company)
        Section(company.displayName) {
            ForEach(Array(selected.enumerated()), id: \.element) { _, idx in
                if let entry = pool.first(where: { $0.index == idx }) {
                    BulletRowView(entry: entry) {
                        swapTarget = SwapTarget(company: company, bulletIndex: idx)
                    }
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

    // MARK: - Rebuild action

    private func rebuild() async {
        isRebuilding = true
        rebuildError = nil
        do {
            let (latex, pdfData) = try await CVService.rebuild(decisions: decisions, jd: jd)
            let updated = CVResult(latex: latex, pdfData: pdfData, decisions: decisions, pools: pools)
            CVCacheStore.save(updated, for: jobId)
            onRebuild(latex, pdfData)
            dismiss()
        } catch {
            rebuildError = error.localizedDescription
        }
        isRebuilding = false
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
                Button(action: onSwap) {
                    Label("Replace", systemImage: "arrow.left.arrow.right")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.indigo)
                }
                .buttonStyle(.plain)
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
    @Binding var selected: Set<String>
    var onDone: (Set<String>) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var localSelected: Set<String> = []

    var body: some View {
        NavigationStack {
            List(allSkills, id: \.self) { skill in
                Button {
                    if localSelected.contains(skill) {
                        localSelected.remove(skill)
                    } else {
                        localSelected.insert(skill)
                    }
                } label: {
                    HStack {
                        Text(skill).font(.system(size: 14)).foregroundColor(.primary)
                        Spacer()
                        if localSelected.contains(skill) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.indigo)
                        } else {
                            Image(systemName: "circle").foregroundColor(.secondary)
                        }
                    }
                }
            }
            .listStyle(.plain)
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
        .onAppear { localSelected = selected }
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
        }
    }
}
