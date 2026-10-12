import SwiftUI

struct QuickCVView: View {
    let profile: String
    @Environment(\.dismiss) private var dismiss

    @State private var jdText = ""
    @State private var isGenerating = false
    @State private var error: String?
    @State private var cvResult: CVResult?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $jdText)
                    .font(.system(size: 15))
                    .padding(12)
                    .overlay(alignment: .topLeading) {
                        if jdText.isEmpty {
                            Text("Paste job description here…")
                                .foregroundColor(.secondary)
                                .font(.system(size: 15))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 20)
                                .allowsHitTesting(false)
                        }
                    }

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                generateButton
            }
            .navigationTitle("Quick CV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $cvResult) { result in
                CVPreviewView(jd: jdText, jobId: -1, profile: profile, result: result)
            }
        }
    }

    private var generateButton: some View {
        let isEmpty = jdText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button(action: generate) {
            Group {
                if isGenerating {
                    ProgressView().tint(.white)
                } else {
                    Text("Generate CV").fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .background(isEmpty || isGenerating ? Color.secondary : Color.indigo)
        .foregroundColor(.white)
        .disabled(isEmpty || isGenerating)
        .padding()
    }

    private func generate() {
        isGenerating = true
        error = nil
        Task {
            do {
                let result = try await CVService.generateCV(jd: jdText, profile: profile)
                cvResult = result
            } catch {
                self.error = error.localizedDescription
            }
            isGenerating = false
        }
    }
}
