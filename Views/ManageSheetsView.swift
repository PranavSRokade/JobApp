import SwiftUI

struct ManageSheetsView: View {
    @ObservedObject var vm: JobsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var editMode: EditMode = .inactive
    @State private var showConfirm = false

    var body: some View {
        NavigationStack {
            List(vm.availableSheets, id: \.self, selection: $selected) { sheet in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatSheetName(sheet))
                            .font(.body)
                        Text(sheet)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if sheet == vm.sheetName {
                        Text("Active")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard editMode == .inactive else { return }
                    vm.selectedSheet = sheet
                    dismiss()
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, $editMode)
            .navigationTitle("Sheets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        if editMode == .active {
                            editMode = .inactive
                            selected = []
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if editMode == .active {
                        Button("Select All") {
                            selected = Set(vm.availableSheets)
                        }
                    } else {
                        Button("Select") {
                            editMode = .active
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if editMode == .active && !selected.isEmpty {
                    deleteBar
                }
            }
        }
        .confirmationDialog(
            "Delete \(selected.count) sheet\(selected.count == 1 ? "" : "s")?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete \(selected.count) sheet\(selected.count == 1 ? "" : "s")", role: .destructive) {
                let toDelete = selected
                selected = []
                editMode = .inactive
                dismiss()
                Task { await vm.bulkDeleteSheets(toDelete) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var deleteBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text("\(selected.count) selected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    selected = []
                } label: {
                    Text("Clear")
                        .foregroundColor(.secondary)
                }
                Button {
                    showConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }
}

private func formatSheetName(_ raw: String) -> String {
    let pattern = /^(\d{2})-(\d{2})(AM|PM)_(\d{2})-([A-Za-z]{3})-(\d{2})$/
    guard let match = try? pattern.wholeMatch(in: raw) else { return raw }
    let (_, hh, mm, ampm, dd, month, _) = match.output
    return "\(Int(dd) ?? 0) \(month) · \(Int(hh) ?? 0):\(mm) \(ampm)"
}
