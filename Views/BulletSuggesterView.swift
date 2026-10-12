import SwiftUI

struct BulletSuggesterView: View {
    let profile: String
    @Environment(\.dismiss) private var dismiss

    @State private var description = ""
    @State private var selectedCompany: CVCompany
    @State private var suggestions: [CVProfileService.SuggestedBullet] = []
    @State private var selected: Set<UUID> = []
    @State private var isGenerating = false
    @State private var isSaving = false
    @State private var error: String?
    @State private var savedToast = false

    init(profile: String) {
        self.profile = profile
        _selectedCompany = State(initialValue: CVCompany.cases(for: profile).first ?? .nHabit)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                companyPicker
                    .padding(.horizontal)
                    .padding(.top, 12)

                ZStack(alignment: .topLeading) {
                    if description.isEmpty {
                        Text("Describe a feature or achievement…")
                            .foregroundColor(.secondary)
                            .font(.system(size: 15))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 9)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $description)
                        .font(.system(size: 15))
                        .scrollContentBackground(.hidden)
                        .frame(height: 130)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                            }
                        }
                }
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(.separator), lineWidth: 0.5))
                .padding(.horizontal)
                .padding(.top, 12)

                generateButton
                    .padding(.horizontal)
                    .padding(.top, 10)

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                        .padding(.top, 6)
                }

                if !suggestions.isEmpty {
                    suggestionsList
                }

                Spacer()
            }
            .navigationTitle("Suggest Bullets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                if !selected.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: addSelected) {
                            if isSaving {
                                ProgressView().tint(.indigo)
                            } else {
                                Text("Add \(selected.count)")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.indigo)
                            }
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .overlay {
                if savedToast {
                    VStack {
                        Spacer()
                        Text("Added to pool")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(.thinMaterial, in: Capsule())
                            .padding(.bottom, 40)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: savedToast)
        }
    }

    private var companyPicker: some View {
        let companies = CVCompany.cases(for: profile)
        return Picker("Company", selection: $selectedCompany) {
            ForEach(companies, id: \.self) { co in
                Text(co.displayName(for: profile)).tag(co)
            }
        }
        .pickerStyle(.segmented)
    }

    private var generateButton: some View {
        Button(action: generate) {
            Group {
                if isGenerating {
                    ProgressView().tint(.white)
                } else {
                    Label("Suggest Bullets", systemImage: "wand.and.sparkles")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
        }
        .background(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating
                    ? Color.secondary : Color.indigo)
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
    }

    private var suggestionsList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(suggestions) { bullet in
                    let isOn = selected.contains(bullet.id)
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundColor(isOn ? .indigo : .secondary)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(bullet.displayText)
                                .font(.system(size: 14))
                                .fixedSize(horizontal: false, vertical: true)
                            if !bullet.skills.isEmpty {
                                Text(bullet.skills.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isOn ? Color.indigo.opacity(0.08) : Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isOn { selected.remove(bullet.id) } else { selected.insert(bullet.id) }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 14)
        }
    }

    private func generate() {
        isGenerating = true
        error = nil
        suggestions = []
        selected = []
        Task {
            do {
                suggestions = try await CVProfileService.suggestBullets(
                    description: description,
                    company: selectedCompany.apiKey,
                    profile: profile
                )
            } catch {
                self.error = error.localizedDescription
            }
            isGenerating = false
        }
    }

    private func addSelected() {
        isSaving = true
        error = nil
        let toAdd = suggestions.filter { selected.contains($0.id) }
        let company = selectedCompany
        Task {
            do {
                var prof = try await CVProfileService.fetchProfile(for: profile)
                var pool = prof.bullets.pool(for: company)
                for bullet in toAdd {
                    let newId = "\(company.apiKey)_\(UUID().uuidString.prefix(6).lowercased())"
                    pool.append(CVProfileBullet(id: newId, pinned: false, skills: bullet.skills, latex: bullet.latex))
                }
                prof.bullets.setPool(pool, for: company)
                try await CVProfileService.saveBullets(prof.bullets, for: profile)
                selected = []
                savedToast = true
                Task { try? await Task.sleep(nanoseconds: 2_000_000_000); savedToast = false }
            } catch {
                self.error = error.localizedDescription
            }
            isSaving = false
        }
    }
}

private extension CVProfileService.SuggestedBullet {
    var displayText: String {
        latex
            .replacingOccurrences(of: #"\\textbf\{([^}]*)\}"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\\textit\{([^}]*)\}"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\&", with: "&")
            .replacingOccurrences(of: "\\%", with: "%")
            .trimmingCharacters(in: .whitespaces)
    }
}
