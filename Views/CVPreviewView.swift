import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// "Resume_<Role title>_<Company name>_<City>.pdf" — parts that are unknown are left out,
/// e.g. a job with no company or city gives "Resume_React Native Engineer.pdf".
func resumeFileName(title: String, company: String? = nil, location: String? = nil) -> String {
    documentFileName(prefix: "Resume", title: title, company: company, location: location)
}

/// Same shape as the resume: "Cover Letter_<Role title>_<Company name>_<City>.pdf"
func coverLetterFileName(title: String, company: String? = nil, location: String? = nil) -> String {
    documentFileName(prefix: "Cover Letter", title: title, company: company, location: location)
}

private func documentFileName(prefix: String, title: String, company: String?, location: String?) -> String {
    func clean(_ s: String) -> String {
        s.replacingOccurrences(of: #"\([^)]*\)|\[[^\]]*\]"#, with: "", options: .regularExpression) // "(100% Remote)"
            .replacingOccurrences(of: #"[/\\:*?"<>|_]+"#, with: " ", options: .regularExpression)    // illegal in file names (and our separator)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -,."))
    }
    let parts = [prefix, clean(title), clean(company ?? ""), clean(city(from: location ?? ""))]
        .filter { !$0.isEmpty }
        .map { String($0.prefix(60)) }
    return parts.joined(separator: "_") + ".pdf"
}

/// "London, England, United Kingdom" → "London", "Greater Seattle Area" → "Seattle",
/// "Austin, Texas Metropolitan Area" → "Austin", "United States" → "United States"
func city(from location: String) -> String {
    var first = location.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? ""
    if first.hasPrefix("Greater ") { first.removeFirst("Greater ".count) }
    for suffix in [" Metropolitan Area", " Metro Area", " Bay Area", " Area", " Region"] where first.hasSuffix(suffix) {
        first.removeLast(suffix.count)
        break
    }
    return first.trimmingCharacters(in: .whitespaces)
}

struct CVPreviewView: View {
    let jd: String
    let jobId: Int
    let profile: String
    @State var result: CVResult
    var fileName: String = "Resume.pdf"
    /// False once the job is applied to: the CV is then a record of what was sent
    var canEdit: Bool = true
    var region: String? = nil // the job's market, so an edited CV keeps the right work-rights line

    @State private var showShareOptions = false
    @State private var shareItems: [Any]? = nil
    @State private var showReview = false
    /// The editor opens with these choices: the CV's own, or the CV's with a review's fixes applied
    @State private var editing: EditorSeed?
    /// Set by the review, opened once the review sheet has gone
    @State private var pendingEdit: EditorSeed?

    private struct EditorSeed: Identifiable {
        let id = UUID()
        let decisions: CVDecisions
    }
    @State private var showJD = false
    @State private var showSave = false

    var body: some View {
        NavigationStack {
            PDFKitView(data: result.pdfData)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Generated CV")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if canEdit {
                        ToolbarItem(placement: .navigationBarLeading) {
                            HStack(spacing: 16) {
                                Button("Edit") { editing = EditorSeed(decisions: result.decisions) }
                                Button("Review") { showReview = true }
                            }
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 16) {
                            Button {
                                showJD = true
                            } label: {
                                Label("JD", systemImage: "doc.text")
                                    .labelStyle(.titleAndIcon)
                                    .font(.system(size: 13, weight: .medium))
                            }
                            Button {
                                showSave = true
                            } label: {
                                Image(systemName: "square.and.arrow.down")
                            }
                            Button {
                                showShareOptions = true
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                }
                .sheet(isPresented: $showJD) {
                    JDQuickView(jd: jd)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                }
                .savePDF(isPresented: $showSave, data: result.pdfData, fileName: fileName)
                .confirmationDialog("Share as", isPresented: $showShareOptions, titleVisibility: .visible) {
                    Button("Share PDF") {
                        // The share sheet / "Save to Files" uses the file's name, so name it properly
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                        try? result.pdfData.write(to: tempURL, options: .atomic)
                        shareItems = [tempURL]
                    }
                    Button("Share Overleaf Link") {
                        let b64 = Data(result.latex.utf8).base64EncodedString()
                            .replacingOccurrences(of: "+", with: "-")
                            .replacingOccurrences(of: "/", with: "_")
                            .replacingOccurrences(of: "=", with: "")
                        if let url = URL(string: "https://job-worker.pranavrokade.workers.dev/overleaf#\(b64)") {
                            shareItems = [url]
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .sheet(isPresented: Binding(
                    get: { shareItems != nil },
                    set: { if !$0 { shareItems = nil } }
                )) {
                    if let items = shareItems {
                        ActivityShareSheet(items: items)
                    }
                }
                .sheet(isPresented: $showReview, onDismiss: {
                    editing = pendingEdit
                    pendingEdit = nil
                }) {
                    CVReviewView(jd: jd, result: result, profile: profile) { decisions in
                        pendingEdit = EditorSeed(decisions: decisions)
                        showReview = false
                    }
                }
                .sheet(item: $editing) { seed in
                    CVEditorView(
                        decisions: seed.decisions,
                        pools: result.pools,
                        latex: result.latex,
                        jd: jd,
                        jobId: jobId,
                        profile: profile,
                        region: region
                    ) { newLatex, newPDF, newDecisions in
                        result.latex = newLatex
                        result.pdfData = newPDF
                        result.decisions = newDecisions
                    }
                }
        }
    }
}

// MARK: - JD quick-view bottom sheet

struct JDQuickView: View {
    let jd: String

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(jd)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Job Description")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Save to Files

/// One tap to the Files save picker with the name already filled in, instead of share sheet →
/// "Save to Files". A short "Saved" note confirms it; the exporter's error text shows if it failed.
extension View {
    func savePDF(isPresented: Binding<Bool>, data: Data, fileName: String) -> some View {
        modifier(SavePDFModifier(isPresented: isPresented, data: data, fileName: fileName))
    }
}

private struct SavePDFModifier: ViewModifier {
    @Binding var isPresented: Bool
    let data: Data
    let fileName: String

    private struct Note: Equatable {
        let text: String
        let ok: Bool
    }
    @State private var note: Note? = nil

    func body(content: Content) -> some View {
        content
            .fileExporter(
                isPresented: $isPresented,
                document: PDFFileDocument(data: data),
                contentType: .pdf,
                // the picker appends ".pdf" itself; passing it too gives "Resume.pdf.pdf"
                defaultFilename: (fileName as NSString).deletingPathExtension
            ) { result in
                switch result {
                case .success: show(Note(text: "Saved", ok: true))
                case .failure(let error): show(Note(text: error.localizedDescription, ok: false))
                }
            }
            .overlay(alignment: .bottom) {
                if let note {
                    Label(note.text, systemImage: note.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.medium))
                        .lineLimit(2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: note)
    }

    private func show(_ new: Note) {
        note = new
        Task {
            try? await Task.sleep(for: .seconds(2))
            if note == new { note = nil }
        }
    }
}

/// The exporter wants a FileDocument; the PDF bytes are already rendered, so this just hands them over.
struct PDFFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Generic share sheet via UIActivityViewController

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - PDFKit wrapper

struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = PDFDocument(data: data)
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = PDFDocument(data: data)
    }
}
