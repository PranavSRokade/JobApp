import SwiftUI

// The details job application forms ask for. Saved on the worker, so the Safari extension fills
// forms from the same copy. A field left blank goes back to what the CV header says.
struct ApplyProfileView: View {
    let profileKey: String
    @Environment(\.dismiss) private var dismiss
    @State private var saved: CVProfileService.ApplyProfile? = nil
    @State private var draft = CVProfileService.ApplyProfile()
    @State private var loadError: String? = nil
    @State private var isSaving = false
    @State private var saveError: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if saved != nil {
                    form
                } else if let loadError {
                    VStack(spacing: 12) {
                        Text(loadError).foregroundColor(.secondary).multilineTextAlignment(.center)
                        Button("Try again") { Task { await load() } }
                    }
                    .padding()
                } else {
                    ProgressView("Loading…")
                }
            }
            .navigationTitle("Application Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(saved == nil || draft == saved)
                    }
                }
            }
        }
        .task { await load() }
    }

    private var form: some View {
        Form {
            Section("Name") {
                field("First name", $draft.firstName, content: .givenName)
                field("Last name", $draft.lastName, content: .familyName)
            }
            Section("Contact") {
                field("Email", $draft.email, content: .emailAddress, keyboard: .emailAddress)
                field("Phone", $draft.phone, content: .telephoneNumber, keyboard: .phonePad)
                field("City", $draft.city, content: .addressCity)
                field("Country", $draft.country, content: .countryName)
            }
            Section("Links") {
                field("LinkedIn", $draft.linkedin, content: .URL, keyboard: .URL)
                field("GitHub", $draft.github, content: .URL, keyboard: .URL)
                field("Portfolio", $draft.portfolio, content: .URL, keyboard: .URL)
            }
            Section {
                yesNo("Right to work in the UK", $draft.rightToWork)
                yesNo("Needs visa sponsorship", $draft.needsSponsorship)
                TextField("Note, e.g. visa type and end date", text: $draft.workRightsNote, axis: .vertical)
                    .lineLimit(1...3)
            } header: {
                Text("Work rights")
            }
            Section("Availability") {
                field("Notice period, e.g. 1 month", $draft.noticePeriod)
                field("Salary expectation, e.g. £55,000", $draft.salaryExpectation)
            }
            Section {
                ForEach($draft.answers) { $item in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Question", text: $item.question)
                            .font(.system(size: 14, weight: .semibold))
                        TextField("Your answer", text: $item.answer, axis: .vertical)
                            .lineLimit(1...6)
                            .font(.system(size: 14))
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { draft.answers.remove(atOffsets: $0) }
                Button {
                    draft.answers.append(.init(question: "", answer: ""))
                } label: {
                    Label("Add answer", systemImage: "plus.circle")
                }
            } header: {
                Text("Saved answers")
            } footer: {
                Text("For questions that come up often, like “How did you hear about us?”. Ones missing a question or an answer aren't saved.")
            }
            if let saveError {
                Section { Text(saveError).foregroundColor(.red).font(.footnote) }
            }
        }
    }

    private func field(_ title: String, _ text: Binding<String>, content: UITextContentType? = nil,
                       keyboard: UIKeyboardType = .default) -> some View {
        TextField(title, text: text)
            .textContentType(content)
            .keyboardType(keyboard)
            .textInputAutocapitalization(keyboard == .default ? .sentences : .never)
            .autocorrectionDisabled()
    }

    private func yesNo(_ title: String, _ value: Binding<String>) -> some View {
        Picker(title, selection: value) {
            Text("Not set").tag("")
            Text("Yes").tag("yes")
            Text("No").tag("no")
        }
    }

    private func load() async {
        loadError = nil
        do {
            let apply = try await CVProfileService.fetchApplyProfile(for: profileKey)
            saved = apply
            draft = apply
        } catch {
            loadError = "Couldn't load your details. Check your connection and try again."
        }
    }

    private func save() async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            let apply = try await CVProfileService.saveApplyProfile(draft, for: profileKey)
            saved = apply
            draft = apply
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            saveError = "Couldn't save. Your changes are still here, so try again."
        }
    }
}
