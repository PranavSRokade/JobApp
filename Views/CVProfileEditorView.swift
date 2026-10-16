import SwiftUI
import UniformTypeIdentifiers

struct CVProfileEditorView: View {
    let profileKey: String
    @State private var profile: CVProfile? = nil
    @State private var isLoading = true
    @State private var loadError: String? = nil

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading profile…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundColor(.red)
                    Text(err).multilineTextAlignment(.center).foregroundColor(.secondary)
                    Button("Retry") { Task { await load() } }
                }
                .padding()
            } else if let profile = profile {
                CVProfileTabView(
                    profile: Binding(get: { profile }, set: { self.profile = $0 }),
                    profileKey: profileKey
                )
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            profile = try await CVProfileService.fetchProfile(for: profileKey)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Tab container

private struct CVProfileTabView: View {
    @Binding var profile: CVProfile
    let profileKey: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TabView {
                SkillsPoolTab(skills: $profile.skills, profileKey: profileKey)
                    .tabItem { Label("Skills", systemImage: "list.bullet") }
                BulletsTab(pools: $profile.bullets, profileKey: profileKey)
                    .tabItem { Label("Bullets", systemImage: "text.alignleft") }
                TemplateTab(hasCustomTemplate: $profile.hasCustomTemplate, profileKey: profileKey)
                    .tabItem { Label("Template", systemImage: "doc.text") }
                SettingsTab(
                    settings: Binding(get: { profile.settings ?? .empty }, set: { profile.settings = $0 }),
                    profileKey: profileKey
                )
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .navigationTitle("CV Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Tab 1: Skills Pool

private struct SkillsPoolTab: View {
    @Binding var skills: [String]
    let profileKey: String
    @State private var newSkill = ""
    @State private var isSaving = false
    @State private var saveMessage: String? = nil
    @State private var isError = false

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("New skill…", text: $newSkill)
                        .autocorrectionDisabled()
                    Button {
                        let trimmed = newSkill.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty, !skills.contains(trimmed) else { return }
                        skills.append(trimmed)
                        newSkill = ""
                    } label: {
                        Image(systemName: "plus.circle.fill").foregroundColor(.indigo)
                    }
                    .buttonStyle(.plain)
                }
            }
            Section {
                ForEach(skills, id: \.self) { skill in
                    Text(skill).font(.system(size: 14))
                }
                .onMove { skills.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { skills.remove(atOffsets: $0) }
            } header: {
                Text("Pool — drag to reorder, swipe to delete")
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .safeAreaInset(edge: .bottom) {
            saveBar(isSaving: isSaving, message: saveMessage, isError: isError) {
                Task { await save() }
            }
        }
    }

    private func save() async {
        isSaving = true
        saveMessage = nil
        do {
            try await CVProfileService.saveSkills(skills, for: profileKey)
            saveMessage = "Saved"
            isError = false
        } catch {
            saveMessage = error.localizedDescription
            isError = true
        }
        isSaving = false
    }
}

// MARK: - Tab 2: Bullets

private struct BulletsTab: View {
    @Binding var pools: CVProfileBulletPools
    let profileKey: String
    @State private var selectedCompany: CVCompany = .nHabit
    @State private var editTarget: CVProfileBullet? = nil
    @State private var addingNew = false
    @State private var isSaving = false
    @State private var saveMessage: String? = nil
    @State private var isError = false

    private var currentPool: [CVProfileBullet] { pools.pool(for: selectedCompany) }

    var body: some View {
        List {
            Section {
                Picker("Company", selection: $selectedCompany) {
                    ForEach(CVCompany.cases(for: profileKey), id: \.self) { Text($0.displayName(for: profileKey)).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(currentPool) { bullet in
                    BulletPoolRow(bullet: bullet) {
                        editTarget = bullet
                    }
                }
                .onDelete { indices in
                    var updated = currentPool
                    updated.remove(atOffsets: indices)
                    pools.setPool(updated, for: selectedCompany)
                }
                .onMove { from, to in
                    var updated = currentPool
                    updated.move(fromOffsets: from, toOffset: to)
                    pools.setPool(updated, for: selectedCompany)
                }
                Button {
                    addingNew = true
                } label: {
                    Label("Add Bullet", systemImage: "plus").foregroundColor(.indigo)
                }
            } header: {
                Text("Bullets — tap to edit, swipe to delete")
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .safeAreaInset(edge: .bottom) {
            saveBar(isSaving: isSaving, message: saveMessage, isError: isError) {
                Task { await save() }
            }
        }
        .sheet(item: $editTarget) { bullet in
            BulletEditSheet(bullet: bullet, allSkills: defaultSkillsList) { updated in
                var pool = currentPool
                if let i = pool.firstIndex(where: { $0.id == updated.id }) { pool[i] = updated }
                pools.setPool(pool, for: selectedCompany)
            }
        }
        .sheet(isPresented: $addingNew) {
            BulletEditSheet(
                bullet: CVProfileBullet(id: UUID().uuidString, pinned: false, skills: [], latex: ""),
                allSkills: defaultSkillsList
            ) { newBullet in
                var pool = currentPool
                pool.append(newBullet)
                pools.setPool(pool, for: selectedCompany)
            }
        }
    }

    private func save() async {
        isSaving = true
        saveMessage = nil
        do {
            try await CVProfileService.saveBullets(pools, for: profileKey)
            saveMessage = "Saved"
            isError = false
        } catch {
            saveMessage = error.localizedDescription
            isError = true
        }
        isSaving = false
    }
}

private struct BulletPoolRow: View {
    let bullet: CVProfileBullet
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(bullet.displayText)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if bullet.pinned {
                    Image(systemName: "pin.fill").foregroundColor(.orange).font(.caption)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(bullet.skills.prefix(4), id: \.self) { skill in
                        Text(skill)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.indigo.opacity(0.12))
                            .foregroundColor(.indigo)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Bullet edit sheet

private struct BulletEditSheet: View {
    @State var bullet: CVProfileBullet
    let allSkills: [String]
    var onSave: (CVProfileBullet) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showSkillsPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("LaTeX") {
                    TextEditor(text: $bullet.latex)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minHeight: 120)
                }
                Section {
                    Toggle("Pinned (always included)", isOn: $bullet.pinned)
                } header: {
                    Text("Options")
                }
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Skill Tags")
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                            Text(bullet.skills.isEmpty ? "None" : bullet.skills.joined(separator: ", "))
                                .font(.caption).foregroundColor(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(.secondary).font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { showSkillsPicker = true }
                } header: {
                    Text("Skills (used for AI bullet matching)")
                }
                Section("Preview") {
                    Text(bullet.displayText)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Edit Bullet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(bullet)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(bullet.latex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showSkillsPicker) {
                SkillsPickerView(
                    title: "Skill Tags",
                    subtitle: "Tags used by AI to match this bullet to a JD",
                    allSkills: allSkills,
                    initialSelected: bullet.skills,
                    onDone: { bullet.skills = $0 }
                )
            }
        }
    }
}

// MARK: - Tab 3: Template

private struct TemplateTab: View {
    @Binding var hasCustomTemplate: Bool
    let profileKey: String
    @State private var showPicker = false
    @State private var isSaving = false
    @State private var saveMessage: String? = nil
    @State private var isError = false
    @State private var uploadedPreviewText: String? = nil
    @State private var defaultTemplateText: String? = nil
    @State private var isLoadingDefault = false
    @State private var showDefaultTemplate = false

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: hasCustomTemplate ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(hasCustomTemplate ? .indigo : .secondary)
                    Text(hasCustomTemplate ? "Custom template active" : "Using built-in template")
                        .font(.system(size: 14))
                }
            } header: {
                Text("Status")
            }

            Section {
                HStack {
                    Label("View default template", systemImage: "doc.text.magnifyingglass")
                        .foregroundColor(.indigo)
                    Spacer()
                    if isLoadingDefault {
                        ProgressView().progressViewStyle(.circular).scaleEffect(0.8)
                    } else {
                        Image(systemName: "chevron.right").foregroundColor(.secondary).font(.caption)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isLoadingDefault else { return }
                    if defaultTemplateText != nil {
                        showDefaultTemplate = true
                    } else {
                        Task { await loadDefaultTemplate() }
                    }
                }

                HStack {
                    Label("Upload .tex File", systemImage: "arrow.up.doc")
                        .foregroundColor(.indigo)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { showPicker = true }

                if hasCustomTemplate {
                    Button(role: .destructive) {
                        Task { await deleteTemplate() }
                    } label: {
                        Label("Revert to Built-in", systemImage: "arrow.uturn.left")
                    }
                }
            } header: {
                Text("Actions")
            }

            if let preview = uploadedPreviewText {
                Section {
                    Text(preview)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                } header: {
                    Text("Uploaded template preview")
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            if isSaving || saveMessage != nil {
                saveBar(isSaving: isSaving, message: saveMessage, isError: isError) {}
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showPicker) {
            DocumentPickerView { tex, filename in
                uploadedPreviewText = tex
                Task { await uploadTemplate(tex) }
            }
        }
        .sheet(isPresented: $showDefaultTemplate) {
            if let tex = defaultTemplateText {
                TemplateViewerSheet(tex: tex) { edited in Task { await uploadTemplate(edited) } }
            }
        }
    }

    private func loadDefaultTemplate() async {
        isLoadingDefault = true
        do {
            defaultTemplateText = try await CVProfileService.fetchDefaultTemplate(for: profileKey)
            showDefaultTemplate = true
        } catch {}
        isLoadingDefault = false
    }

    private func uploadTemplate(_ tex: String) async {
        isSaving = true
        saveMessage = nil
        do {
            try await CVProfileService.uploadTemplate(tex, for: profileKey)
            hasCustomTemplate = true
            uploadedPreviewText = tex
            saveMessage = "Template uploaded"
            isError = false
        } catch {
            saveMessage = error.localizedDescription
            isError = true
        }
        isSaving = false
    }

    private func deleteTemplate() async {
        isSaving = true
        saveMessage = nil
        do {
            try await CVProfileService.deleteTemplate(for: profileKey)
            hasCustomTemplate = false
            uploadedPreviewText = nil
            saveMessage = "Reverted to built-in"
            isError = false
        } catch {
            saveMessage = error.localizedDescription
            isError = true
        }
        isSaving = false
    }
}

private struct TemplateViewerSheet: View {
    @State var tex: String
    var onUpload: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: $tex)
                .font(.system(size: 12, design: .monospaced))
                .padding(8)
                .navigationTitle("Default Template")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Close") { dismiss() }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Upload as Custom") {
                            onUpload(tex)
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
    }
}

// MARK: - Document picker wrapper

private struct DocumentPickerView: UIViewControllerRepresentable {
    var onPick: (String, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.plainText, UTType(filenameExtension: "tex") ?? .plainText]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (String, String) -> Void
        init(onPick: @escaping (String, String) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let tex = try? String(contentsOf: url, encoding: .utf8) else { return }
            onPick(tex, url.lastPathComponent)
        }
    }
}

// MARK: - Shared save bar

private func saveBar(isSaving: Bool, message: String?, isError: Bool, onSave: @escaping () -> Void) -> some View {
    VStack(spacing: 6) {
        if let msg = message {
            Text(msg)
                .font(.caption)
                .foregroundColor(isError ? .red : .green)
        }
        Button(action: onSave) {
            Group {
                if isSaving {
                    HStack(spacing: 8) {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("Saving…")
                    }
                } else {
                    Text("Save Changes")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.indigo)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isSaving)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    .background(.ultraThinMaterial)
}

// MARK: - Default skills list (fallback when profile hasn't loaded)

private let defaultSkillsList = [
    "React Native", "TypeScript", "JavaScript", "REST APIs", "Firebase",
    "Google Cloud Platform", "Kotlin", "Android", "iOS", "Java", "Next.js",
    "React", "Supabase", "OpenAI API", "Jetpack Compose", "E2E Testing",
    "Detox", "Reanimated", "Amplitude", "Sentry", "Google Maps",
    "React Native Biometrics", "Face ID", "Touch ID", "MVVM",
    "Clean Architecture", "JUnit", "GitHub", "Git", "State Management",
]

// MARK: - Tab 4: Settings (summary/education text + AI prompt)

private struct SettingsTab: View {
    @Binding var settings: CVSettings
    let profileKey: String
    @State private var isSaving = false
    @State private var saveMessage: String? = nil
    @State private var isError = false
    @State private var showPrompt = false

    var body: some View {
        List {
            Section {
                TextField("e.g. 3.5+", text: $settings.yearsExperience)
                    .autocorrectionDisabled()
            } header: {
                Text("Years of experience")
            } footer: {
                Text("Summary line: “… with N years of experience …”")
            }
            Section {
                TextField("e.g. MSc in Adv. Software Engineering", text: $settings.summaryDegree)
                    .autocorrectionDisabled()
            } header: {
                Text("Degree (summary line)")
            } footer: {
                Text("Short form used in the summary paragraph.")
            }
            Section {
                TextField("e.g. Masters in Advanced Software Engineering $\\vert$ Merit", text: $settings.educationTitle, axis: .vertical)
                    .font(.system(size: 13, design: .monospaced))
                    .autocorrectionDisabled()
            } header: {
                Text("Education heading")
            } footer: {
                Text("Full heading under Education (LaTeX). Shorten it if the CV runs out of space. Leave any field blank to use the built-in default.")
            }
            Section {
                Button { showPrompt = true } label: {
                    HStack {
                        Label("Edit AI prompt", systemImage: "text.badge.star").foregroundColor(.indigo)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(.secondary).font(.caption)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Text("AI")
            } footer: {
                Text("The instructions sent to the model when generating a CV.")
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            saveBar(isSaving: isSaving, message: saveMessage, isError: isError) {
                Task { await save() }
            }
        }
        .sheet(isPresented: $showPrompt) {
            PromptEditorSheet(profileKey: profileKey)
        }
    }

    private func save() async {
        isSaving = true
        saveMessage = nil
        do {
            try await CVProfileService.saveSettings(settings, for: profileKey)
            saveMessage = "Saved"
            isError = false
        } catch {
            saveMessage = error.localizedDescription
            isError = true
        }
        isSaving = false
    }
}

// MARK: - CV prompt editor

private struct PromptEditorSheet: View {
    let profileKey: String
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var defaultText = ""
    @State private var placeholders: [String] = []
    @State private var isCustom = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var message: String? = nil
    @State private var isError = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading prompt…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Image(systemName: isCustom ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isCustom ? .indigo : .secondary)
                            Text(isCustom ? "Custom prompt active" : "Using built-in prompt")
                                .font(.caption)
                            Spacer()
                            if let message {
                                Text(message).font(.caption).foregroundColor(isError ? .red : .green)
                            }
                        }
                        .padding(.horizontal).padding(.vertical, 8)
                        Divider()
                        TextEditor(text: $text)
                            .font(.system(size: 12, design: .monospaced))
                            .autocorrectionDisabled()
                            .padding(8)
                        Divider()
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(placeholders, id: \.self) { p in
                                    Text("{{\(p)}}")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .background(Color.indigo.opacity(0.12))
                                        .foregroundColor(.indigo)
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal).padding(.vertical, 6)
                        }
                    }
                }
            }
            .navigationTitle("CV Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        Button("Reset") { Task { await reset() } }
                            .disabled(isSaving || !isCustom)
                        Button("Save") { Task { await save() } }
                            .fontWeight(.semibold)
                            .disabled(isSaving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        do {
            let info = try await CVProfileService.fetchPrompt(for: profileKey)
            text = info.prompt
            defaultText = info.defaultPrompt
            placeholders = info.placeholders
            isCustom = info.isCustom
        } catch {
            message = error.localizedDescription
            isError = true
        }
        isLoading = false
    }

    private func save() async {
        isSaving = true
        message = nil
        do {
            try await CVProfileService.savePrompt(text, for: profileKey)
            isCustom = true
            message = "Saved"
            isError = false
        } catch {
            message = error.localizedDescription
            isError = true
        }
        isSaving = false
    }

    private func reset() async {
        isSaving = true
        message = nil
        do {
            try await CVProfileService.resetPrompt(for: profileKey)
            text = defaultText
            isCustom = false
            message = "Reset to built-in"
            isError = false
        } catch {
            message = error.localizedDescription
            isError = true
        }
        isSaving = false
    }
}
