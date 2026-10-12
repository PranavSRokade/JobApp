import SwiftUI

struct JobsListView: View {
    @StateObject private var vm = JobsViewModel()
    @State private var sheetToDelete: String? = nil
    @State private var showManageSheets = false
    @State private var showProfileEditor = false
    @State private var showFilters = false
    @State private var showQuickCV = false
    @State private var showBulletSuggester = false
    @State private var showFeatureChats = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.jobs.isEmpty {
                    ProgressView("Loading jobs…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = vm.errorMessage {
                    ContentUnavailableView(
                        "Failed to load",
                        systemImage: "wifi.exclamationmark",
                        description: Text(error)
                    )
                } else if vm.showStarredOnly && vm.filteredJobs.isEmpty {
                    ContentUnavailableView(
                        "No starred jobs",
                        systemImage: "star",
                        description: Text("Swipe right on a job to star it")
                    )
                } else {
                    List(vm.filteredJobs) { job in
                        NavigationLink(destination: JobDetailView(job: job, sheetName: vm.sheetName, starredStore: vm.starredStore, profile: vm.selectedProfile)) {
                            JobRowView(job: job, sheetName: vm.sheetName, starredStore: vm.starredStore)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await vm.load() }
                    .searchable(text: $vm.searchText, prompt: "Search jobs…")
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                regionPicker
            }
            .navigationTitle(vm.showStarredOnly ? "\(vm.filteredJobs.count) Starred" : "\(vm.filteredJobs.count) Jobs")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { vm.showStarredOnly.toggle() } label: {
                            Label(vm.showStarredOnly ? "Show All" : "Show Starred",
                                  systemImage: vm.showStarredOnly ? "star.slash" : "star")
                        }
                        Button { showFilters = true } label: {
                            Label(vm.filtersStore.filters.isDefault ? "Filters" : "Filters (active)",
                                  systemImage: vm.filtersStore.filters.isDefault ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        }
                        Divider()
                        Button { showFeatureChats = true } label: {
                            Label("Feature Chats", systemImage: "text.bubble")
                        }
                        Button { showBulletSuggester = true } label: {
                            Label("Suggest Bullets", systemImage: "wand.and.sparkles")
                        }
                        Button { showQuickCV = true } label: {
                            Label("Quick CV", systemImage: "doc.text.below.ecg")
                        }
                        Divider()
                        Button { showProfileEditor = true } label: {
                            Label("Edit Profile", systemImage: "person.crop.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if !vm.availableSheets.isEmpty {
                        sheetPicker
                    }
                }
            }
        }
        .task { await vm.load() }
        .sheet(isPresented: $showManageSheets) {
            ManageSheetsView(vm: vm)
        }
        .sheet(isPresented: $showProfileEditor) {
            CVProfileEditorView(profileKey: vm.selectedProfile)
        }
        .sheet(isPresented: $showBulletSuggester) {
            BulletSuggesterView(profile: vm.selectedProfile)
        }
        .sheet(isPresented: $showQuickCV) {
            QuickCVView(profile: vm.selectedProfile)
        }
        .sheet(isPresented: $showFeatureChats) {
            FeatureChatsListView(store: vm.chatStore, profile: vm.selectedProfile)
        }
        .sheet(isPresented: $showFilters) {
            JobFiltersView(store: vm.filtersStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Delete \(sheetToDelete.map { formatSheetName($0) } ?? "")?",
            isPresented: Binding(get: { sheetToDelete != nil }, set: { if !$0 { sheetToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let sheet = sheetToDelete {
                    Task { await vm.deleteSheet(sheet) }
                }
                sheetToDelete = nil
            }
            Button("Cancel", role: .cancel) { sheetToDelete = nil }
        }
    }

    private var regionPicker: some View {
        Picker("Region", selection: $vm.region) {
            Text("🇬🇧 UK").tag("uk")
            Text("🇺🇸 USA").tag("us")
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var sheetPicker: some View {
        Menu {
            ForEach(vm.availableSheets, id: \.self) { sheet in
                Menu(formatSheetName(sheet) + (vm.sheetsWithStars.contains(sheet) ? " ★" : "")) {
                    Button {
                        vm.selectedSheet = sheet
                    } label: {
                        Label("View", systemImage: sheet == vm.sheetName ? "checkmark" : "eye")
                    }
                    Button(role: .destructive) {
                        sheetToDelete = sheet
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            Divider()
            Button {
                showManageSheets = true
            } label: {
                Label("Manage Sheets…", systemImage: "slider.horizontal.3")
            }
        } label: {
            HStack(spacing: 3) {
                Text(vm.sheetName.map { formatSheetName($0) } ?? "Latest")
                    .font(.caption)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
        }
    }


}

// "03-42AM_18-Jun-26" or "US_03-42AM_18-Jun-26" → "18 Jun · 3:42 AM"
private func formatSheetName(_ raw: String) -> String {
    let name = raw.replacingOccurrences(of: #"^[A-Z]{2}_"#, with: "", options: .regularExpression)
    let pattern = /^(\d{2})-(\d{2})(AM|PM)_(\d{2})-([A-Za-z]{3})-(\d{2})$/
    guard let match = try? pattern.wholeMatch(in: name) else { return raw }
    let (_, hh, mm, ampm, dd, month, _) = match.output
    let hour = Int(hh) ?? 0
    return "\(Int(dd) ?? 0) \(month) · \(hour):\(mm) \(ampm)"
}
