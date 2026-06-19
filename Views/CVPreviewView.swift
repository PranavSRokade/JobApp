import SwiftUI
import PDFKit

struct CVPreviewView: View {
    let pdfData: Data
    let latex: String

    @State private var showShareOptions = false
    @State private var shareItems: [Any]? = nil

    var body: some View {
        NavigationStack {
            PDFKitView(data: pdfData)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Generated CV")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
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
                        try? pdfData.write(to: tempURL)
                        shareItems = [tempURL]
                    }
                    Button("Share Overleaf Link") {
                        // Encode LaTeX as base64url in the URL fragment.
                        // The fragment is never sent to the server, so no 414.
                        // Our /overleaf page reads it client-side and form-POSTs to Overleaf.
                        let b64 = Data(latex.utf8).base64EncodedString()
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

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
