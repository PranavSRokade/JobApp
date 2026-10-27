import SwiftUI
import PDFKit

/// "Resume_<Role title>_<Company name>_<City>.pdf" — parts that are unknown are left out,
/// e.g. Quick CV (pasted JD) gives "Resume_React Native Engineer.pdf".
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

    @State private var showShareOptions = false
    @State private var shareItems: [Any]? = nil
    @State private var showEditor = false
    @State private var showJD = false

    var body: some View {
        NavigationStack {
            PDFKitView(data: result.pdfData)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Generated CV")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if canEdit {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Edit") { showEditor = true }
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
                .sheet(isPresented: $showEditor) {
                    CVEditorView(
                        decisions: result.decisions,
                        pools: result.pools,
                        latex: result.latex,
                        jd: jd,
                        jobId: jobId,
                        profile: profile
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
