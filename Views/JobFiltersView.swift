import SwiftUI

struct JobFiltersView: View {
    @ObservedObject var store: JobFiltersStore
    @Environment(\.dismiss) private var dismiss

    @State private var newCompany = ""
    @State private var newAllowed = ""
    @State private var newBlocked = ""

    var body: some View {
        NavigationStack {
            List {
                toggleSection
                allowedSection
                blockedSection
                companiesSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !store.filters.isDefault {
                        Button("Reset", role: .destructive) {
                            store.filters.hideOver100 = false
                            store.filters.excludedCompanies = []
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
    }

    // MARK: - Toggles

    private var toggleSection: some View {
        Section("Other") {
            Toggle("Hide 100+ applicant jobs", isOn: $store.filters.hideOver100)
        }
    }

    // MARK: - Allowed title keywords

    private var allowedSection: some View {
        Section {
            if !store.filters.allowedTitleKeywords.isEmpty {
                TagsRow(items: store.filters.allowedTitleKeywords, color: .green) { item in
                    store.filters.allowedTitleKeywords.removeAll { $0 == item }
                }
            }
            HStack {
                TextField("e.g. react native, mobile", text: $newAllowed)
                    .submitLabel(.done)
                    .onSubmit { addAllowed() }
                Button(action: addAllowed) {
                    Image(systemName: "plus.circle.fill").foregroundColor(.green)
                }
                .disabled(newAllowed.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Title Must Include (Allowed)")
        } footer: {
            Text("Job title must match at least one keyword. Empty = show all. Tap a tag to remove.")
                .font(.caption)
        }
    }

    // MARK: - Blocked title keywords

    private var blockedSection: some View {
        Section {
            if !store.filters.blockedTitleKeywords.isEmpty {
                TagsRow(items: store.filters.blockedTitleKeywords, color: .orange) { item in
                    store.filters.blockedTitleKeywords.removeAll { $0 == item }
                }
            }
            HStack {
                TextField("e.g. senior, lead, backend", text: $newBlocked)
                    .submitLabel(.done)
                    .onSubmit { addBlocked() }
                Button(action: addBlocked) {
                    Image(systemName: "plus.circle.fill").foregroundColor(.orange)
                }
                .disabled(newBlocked.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Title Must Not Include (Blocked)")
        } footer: {
            Text("Jobs whose title contains any of these are hidden. Tap a tag to remove.")
                .font(.caption)
        }
    }

    // MARK: - Company blacklist

    private var companiesSection: some View {
        Section {
            if !store.filters.excludedCompanies.isEmpty {
                TagsRow(items: store.filters.excludedCompanies, color: .red) { item in
                    store.filters.excludedCompanies.removeAll { $0 == item }
                }
            }
            HStack {
                TextField("Company name", text: $newCompany)
                    .submitLabel(.done)
                    .onSubmit { addCompany() }
                Button(action: addCompany) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.red)
                }
                .disabled(newCompany.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Excluded Companies")
        } footer: {
            Text("Jobs from any matching company are hidden. Tap a tag to remove it.")
                .font(.caption)
        }
    }

    private func addAllowed() {
        let kw = newAllowed.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty, !store.filters.allowedTitleKeywords.contains(kw) else { return }
        store.filters.allowedTitleKeywords.append(kw)
        newAllowed = ""
    }

    private func addBlocked() {
        let kw = newBlocked.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty, !store.filters.blockedTitleKeywords.contains(kw) else { return }
        store.filters.blockedTitleKeywords.append(kw)
        newBlocked = ""
    }

    private func addCompany() {
        let name = newCompany.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !store.filters.excludedCompanies.contains(name) else { return }
        store.filters.excludedCompanies.append(name)
        newCompany = ""
    }
}

// MARK: - Tags row (inline chips, tap to remove)

private struct TagsRow: View {
    let items: [String]
    let color: Color
    let onRemove: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 4) {
                    Text(item)
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(color.opacity(0.12))
                .foregroundColor(color)
                .clipShape(Capsule())
                .onTapGesture { onRemove(item) }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Simple flow layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

