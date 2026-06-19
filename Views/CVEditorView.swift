import SwiftUI

struct CVEditorView: View {
    @State var decisions: CVDecisions
    let pools: CVBulletPools
    let jd: String
    var onRebuild: (String, Data) -> Void

    @State private var isRebuilding = false
    @State private var rebuildError: String?
    @State private var swapTarget: SwapTarget?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                companySection(.nHabit)
                companySection(.campConnection)
                companySection(.projexino)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Edit Bullets")
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
        }
    }

    // MARK: - Section builder

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
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.indigo)
                            } else if isSelected {
                                Image(systemName: "minus.circle")
                                    .foregroundColor(.secondary)
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
