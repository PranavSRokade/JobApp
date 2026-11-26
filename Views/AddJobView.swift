import SwiftUI

/// Adds a job by hand. Save reads the job ad from the link; when that fails (or there is no link)
/// it asks for the ad to be pasted. The job then opens on its own page to make and edit the CV and
/// letter, and it counts as applied only once "Mark as applied" is tapped there.
struct AddJobView: View {
    @ObservedObject var addedStore: AddedJobsStore
    @ObservedObject var applicationsStore: ApplicationsStore
    let starredStore: StarredJobsStore
    let profile: String
    @State var region: String

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var company = ""
    @State private var link = ""
    @State private var location = ""
    @State private var jd = ""
    /// Why the job-ad box is showing after a save: the link failed, or its text needs a look
    @State private var jdNote: String?
    @State private var fetching = false
    @State private var added: AddedJob?

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasLink: Bool { !trimmed(link).isEmpty }
    /// The box shows with no link to read, or once reading the link fell short
    private var asksForJD: Bool { !hasLink || jdNote != nil }
    private var canSave: Bool {
        !trimmed(title).isEmpty && !trimmed(company).isEmpty && !fetching && added == nil
            && (!asksForJD || !trimmed(jd).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Job") {
                    TextField("Role", text: $title)
                    TextField("Company", text: $company)
                    TextField("Link to the job ad", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: link) { jdNote = nil }
                    TextField("Location (optional)", text: $location)
                }
                Section {
                    Picker("Market", selection: $region) {
                        Text("UK").tag("uk")
                        Text("USA").tag("us")
                        Text("Remote").tag("ww")
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("The page it is listed on, and the market its CV is written for.")
                }
                if asksForJD {
                    Section {
                        TextEditor(text: $jd).frame(minHeight: 180)
                    } header: {
                        Text("Job ad")
                    } footer: {
                        Text(jdNote ?? "With no link, paste the job ad here.")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.disabled(fetching)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if fetching {
                        HStack(spacing: 6) {
                            ProgressView()
                            Text("Reading the ad…").font(.footnote).foregroundStyle(.secondary)
                        }
                    } else {
                        Button("Save", action: save).fontWeight(.semibold).disabled(!canSave)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .interactiveDismissDisabled(fetching)
            .navigationDestination(isPresented: Binding(get: { added != nil }, set: { if !$0 { dismiss() } })) {
                if let added {
                    JobDetailView(job: added.job, sheetName: nil, starredStore: starredStore,
                                  applicationsStore: applicationsStore, profile: profile, region: added.region)
                        .navigationBarBackButtonHidden(true)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Done") { dismiss() }
                            }
                        }
                }
            }
        }
    }

    private func save() {
        guard !asksForJD else { finish(jd: trimmed(jd)); return }
        fetching = true
        Task {
            do {
                let ad = try await JobsService.fetchJobAd(url: trimmed(link), profile: profile)
                if ad.source == "page" {
                    // Plain page text can carry menus and cookie notices: show it before using it
                    jd = ad.jd
                    jdNote = "This is the page's text, not a job listing. Trim it to the job ad, then save."
                } else {
                    finish(jd: ad.jd)
                }
            } catch {
                let reason = error.localizedDescription.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
                jdNote = "Couldn't read the job ad from that link (\(reason)). Paste it here."
            }
            fetching = false
        }
    }

    private func finish(jd: String) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        added = addedStore.add(
            title: trimmed(title), company: trimmed(company), link: trimmed(link),
            location: trimmed(location), jd: jd, region: region,
            taken: { applicationsStore.isApplied($0) }
        )
    }
}
