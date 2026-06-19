import SwiftUI
import PDFKit

struct CVPreviewView: View {
    let jd: String
    let jobId: Int
    @State var result: CVResult

    @State private var showShareOptions = false
    @State private var shareItems: [Any]? = nil
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            PDFKitView(data: result.pdfData)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Generated CV")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Edit") { showEditor = true }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showShareOptions = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                .confirmationDialog("Share as", isPresented: $showShareOptions, titleVisibility: .visible) {
                    Button("Share PDF") {
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("CV.pdf")
                        try? result.pdfData.write(to: tempURL)
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
                        jd: jd,
                        jobId: jobId
                    ) { newLatex, newPDF in
                        result.latex = newLatex
                        result.pdfData = newPDF
                    }
                }
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
