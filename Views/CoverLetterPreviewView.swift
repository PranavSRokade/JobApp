import SwiftUI
import PDFKit

struct CoverLetterPreviewView: View {
    let pdfData: Data
    let jobTitle: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFKitView(data: pdfData)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Cover Letter")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if let url = exportURL {
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                }
        }
    }

    private var exportURL: URL? {
        let name = "Cover Letter - \(jobTitle).pdf"
            .replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? pdfData.write(to: url)
        return url
    }
}
