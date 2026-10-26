import SwiftUI
import UniformTypeIdentifiers

/// Manage the UK sponsor register: see which month's sheet is loaded, check gov.uk for a
/// newer one, or import a downloaded CSV by hand.
struct SponsorRegisterView: View {
    @ObservedObject private var store = SponsorRegisterStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let meta = store.meta {
                        row("Sheet date", meta.sheetDate)
                        row("Companies", meta.count.formatted())
                        row("Imported", meta.importedAt.formatted(date: .abbreviated, time: .shortened))
                        row("Source", meta.source)
                        if let checked = meta.lastCheckedAt {
                            row("Last gov.uk check", checked.formatted(date: .abbreviated, time: .shortened))
                        }
                    } else if store.isLoading || store.isImporting {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(store.isImporting ? "Importing register…" : "Loading register…")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("No register loaded yet — it downloads automatically from gov.uk on launch, or import the CSV below.")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    if store.isStale && store.meta != nil {
                        Label("This sheet is over 45 days old — check for a newer one", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.orange)
                    }
                } header: {
                    Text("Current register")
                } footer: {
                    Text("Home Office register of licensed sponsors (Worker routes). Jobs are matched against it by company name — no AI involved.")
                }

                Section {
                    Button {
                        Task { await store.checkForUpdate(force: true) }
                    } label: {
                        HStack {
                            Label("Check gov.uk for a new sheet", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if store.isChecking || store.isImporting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(store.isChecking || store.isImporting)

                    Button {
                        showPicker = true
                    } label: {
                        Label("Import CSV file…", systemImage: "arrow.up.doc")
                    }
                    .disabled(store.isImporting)

                    if let result = store.lastCheckResult {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Update")
                } footer: {
                    Text("The app also checks gov.uk by itself every few days, so this usually stays current without any action.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Sponsor Register")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showPicker) {
                CSVPickerView { data, filename in
                    Task { await store.importPickedFile(data: data, filename: filename) }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 14))
            Spacer()
            Text(value).font(.system(size: 14)).foregroundColor(.secondary)
        }
    }
}

// MARK: - CSV document picker

private struct CSVPickerView: UIViewControllerRepresentable {
    var onPick: (Data, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.commaSeparatedText, .plainText, UTType(filenameExtension: "csv") ?? .plainText]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (Data, String) -> Void
        init(onPick: @escaping (Data, String) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            onPick(data, url.lastPathComponent)
        }
    }
}
