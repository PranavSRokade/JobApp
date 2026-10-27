import SwiftUI
import PDFKit

struct CoverLetterPreviewView: View {
    @State var letter: CoverLetterResult
    let jobTitle: String
    let profile: String
    @Environment(\.dismiss) private var dismiss

    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            PDFKitView(data: letter.pdfData)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Cover Letter")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 16) {
                            Button("Edit") { showEditor = true }
                            if let url = exportURL {
                                ShareLink(item: url) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                        }
                    }
                }
                .sheet(isPresented: $showEditor) {
                    // Seeded from the current text, so re-opening after a rebuild shows the latest version
                    CoverLetterEditorView(text: letter.text, profile: profile) { newText, newPDF in
                        letter.text = newText
                        letter.pdfData = newPDF
                    }
                }
        }
    }

    private var exportURL: URL? {
        let name = "Cover Letter - \(jobTitle).pdf"
            .replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? letter.pdfData.write(to: url)
        return url
    }
}

// MARK: - Editor sheet

/// Plain-text editor for the generated letter. "Rebuild PDF" sends the edited text to the worker's
/// render endpoint (no AI call) and hands the new PDF + text back to the preview.
struct CoverLetterEditorView: View {
    @State private var text: String
    let profile: String
    let onRebuild: (String, Data) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var isRebuilding = false
    @State private var error: String? = nil

    init(text: String, profile: String, onRebuild: @escaping (String, Data) -> Void) {
        _text = State(initialValue: text)
        self.profile = profile
        self.onRebuild = onRebuild
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $text)
                    .font(.system(size: 15))
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .scrollDismissesKeyboard(.interactively)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                        }
                    }

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                Text("Blank line between paragraphs. Curly quotes and emoji are dropped in the PDF.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            .navigationTitle("Edit Cover Letter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isRebuilding)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        rebuild()
                    } label: {
                        if isRebuilding {
                            ProgressView()
                        } else {
                            Text("Rebuild PDF").fontWeight(.semibold)
                        }
                    }
                    .disabled(isRebuilding || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(isRebuilding)
        }
    }

    private func rebuild() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        isRebuilding = true
        error = nil
        Task {
            do {
                let pdf = try await CVService.renderCoverLetter(text: text, profile: profile)
                onRebuild(text, pdf)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            isRebuilding = false
        }
    }
}
