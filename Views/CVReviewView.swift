import SwiftUI

/// Compares a finished CV with its job ad and lists what the ad asks for that the CV does not show.
/// A gap one of your own bullets or skills covers can be ticked and applied in the editor; a gap
/// nothing covers opens the bullet writer, so a new bullet only ever says what you write.
struct CVReviewView: View {
    let jd: String
    let result: CVResult
    let profile: String
    /// The CV's choices with the ticked fixes applied, to open in the editor
    var onOpenEditor: (CVDecisions) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var gaps: [CVGap]?
    @State private var bullets: CVProfileBulletPools?
    @State private var error: String?
    @State private var chosen: Set<Int> = []
    @State private var writing: WriteTarget?
    @State private var written: Set<Int> = []

    private struct WriteTarget: Identifiable {
        let id: Int
        let company: CVCompany
        let about: String
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Review CV")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Close") { dismiss() }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if let gaps, !gaps.isEmpty { applyBar }
                }
                .task { if gaps == nil { await load() } }
                .sheet(item: $writing) { target in
                    BulletSuggesterView(profile: profile, company: target.company, description: "\(target.about): ") {
                        written.insert(target.id)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error {
            ContentUnavailableView {
                Label("Review failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try again") { Task { await load() } }
            }
        } else if let gaps {
            if gaps.isEmpty {
                ContentUnavailableView("Nothing missing", systemImage: "checkmark.seal",
                                       description: Text("The CV already covers what this job ad asks for."))
            } else {
                List {
                    Section {
                        ForEach(Array(gaps.enumerated()), id: \.offset) { i, gap in
                            gapRow(i, gap)
                        }
                    } footer: {
                        Text("Only add what you have really done. Ticked swaps and skills are applied in the editor, where you rebuild the CV.")
                    }
                }
            }
        } else {
            ProgressView("Comparing your CV with the job ad…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func gapRow(_ i: Int, _ gap: CVGap) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(gap.gap).font(.headline)
            Text(gap.why).font(.subheadline).foregroundStyle(.secondary)
            switch gap.fix.kind {
            case "swap":
                if let company = gap.fix.company.flatMap(CVCompany.init(rawValue:)), let add = gap.fix.add, let replace = gap.fix.replace {
                    tickable(i, title: "Swap in one of your \(company.displayName(for: profile)) bullets") {
                        Text(bulletText(company, add)).font(.footnote)
                        Text("Instead of: \(bulletText(company, replace))").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            case "skill":
                if let skill = gap.fix.skill {
                    tickable(i, title: "Add \(skill) to the skills line") { EmptyView() }
                }
            default:
                let company = gap.fix.company.flatMap(CVCompany.init(rawValue:)) ?? .nHabit
                if written.contains(i) {
                    Label("Saved to your \(company.displayName(for: profile)) bullets. Swap it in from the editor.", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                } else {
                    Button {
                        writing = WriteTarget(id: i, company: company, about: gap.fix.about ?? gap.gap)
                    } label: {
                        Label("Write a bullet if you have done this", systemImage: "square.and.pencil")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func tickable<Detail: View>(_ i: Int, title: String, @ViewBuilder detail: () -> Detail) -> some View {
        let on = chosen.contains(i)
        return Button {
            if on { chosen.remove(i) } else { chosen.insert(i) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Color.accentColor : .secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.footnote.weight(.semibold))
                    detail()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var applyBar: some View {
        Button {
            onOpenEditor(applied())
        } label: {
            Text(chosen.isEmpty ? "Open the editor" : "Apply \(chosen.count) in the editor")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .buttonStyle(.borderedProminent)
        .padding()
        .background(.bar)
    }

    private func bulletText(_ company: CVCompany, _ index: Int) -> String {
        let live = bullets?.pool(for: company)
        if let live, live.indices.contains(index - 1) { return live[index - 1].displayText }
        return result.pools.pool(for: company).first { $0.index == index }?.displayText ?? "Bullet \(index)"
    }

    /// The CV's choices with every ticked swap and skill applied
    private func applied() -> CVDecisions {
        var d = result.decisions
        for i in chosen.sorted() {
            guard let gap = gaps?[i] else { continue }
            if gap.fix.kind == "swap", let company = gap.fix.company.flatMap(CVCompany.init(rawValue:)),
               let add = gap.fix.add, let replace = gap.fix.replace {
                var picked = company.selectedIndices(in: d)
                if let pos = picked.firstIndex(of: replace), !picked.contains(add) {
                    picked[pos] = add
                    d.setSelectedIndices(picked, for: company)
                }
            } else if gap.fix.kind == "skill", let skill = gap.fix.skill {
                let line = d.skillsLine.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if !line.contains(where: { $0.caseInsensitiveCompare(skill) == .orderedSame }) {
                    d.skillsLine = (line + [skill]).filter { !$0.isEmpty }.joined(separator: ", ")
                }
            }
        }
        return d
    }

    private func load() async {
        error = nil
        do {
            async let review = CVService.review(jd: jd, latex: result.latex, decisions: result.decisions, profile: profile)
            async let profileData = try? CVProfileService.fetchProfile(for: profile)
            let (found, fresh) = try await (review, profileData)
            bullets = fresh?.bullets
            gaps = found
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private extension CVDecisions {
    mutating func setSelectedIndices(_ indices: [Int], for company: CVCompany) {
        switch company {
        case .nHabit: nHabitBullets = indices
        case .campConnection: campBullets = indices
        case .projexino: projexinoBullets = indices
        case .samyak: samyakBullets = indices
        }
    }
}
