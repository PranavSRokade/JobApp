import SwiftUI

struct JobsListView: View {
    @ObservedObject var vm: JobsViewModel
    @State private var sheetToDelete: String? = nil
    @State private var showManageSheets = false
    @State private var showProfileEditor = false
    @State private var showApplyProfile = false
    @State private var showFilters = false
    // Visa mode filters on the register, so the list must recompute once the sheet finishes parsing
    @ObservedObject private var sponsorStore = SponsorRegisterStore.shared
    @State private var showAddJob = false
    @State private var showBulletSuggester = false
    @State private var showFeatureChats = false
    @State private var showSponsorRegister = false
    @State private var showPipelineStatus = false

    var body: some View {
        NavigationStack {
            // UK, USA and Remote are real, independent pages: swipe between them (or tap the tabs)
            // and each keeps its own data and scroll position — no reload flash.
            TabView(selection: $vm.region) {
                regionPage(vm.uk).tag("uk")
                regionPage(vm.us).tag("us")
                regionPage(vm.ww).tag("ww")
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .safeAreaInset(edge: .top, spacing: 0) {
                MarketTabs(region: $vm.region)
            }
            // Once, on the pager: a .searchable on each market's List left three competing for the
            // one navigation bar, and the field never showed
            .searchable(text: $vm.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search jobs…")
            .navigationTitle(pageTitle)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Menu {
                            Picker("Sort", selection: $vm.sortMode) {
                                ForEach(JobSortMode.allCases) { mode in
                                    Label(mode.title, systemImage: mode == .visa ? "checkmark.shield" : "list.bullet").tag(mode)
                                }
                            }
                        } label: {
                            Label("Sort: \(vm.sortMode.title)", systemImage: "arrow.up.arrow.down")
                        }
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
                        Button { showAddJob = true } label: {
                            Label("Add Job", systemImage: "plus.rectangle.on.rectangle")
                        }
                        Divider()
                        Button { showProfileEditor = true } label: {
                            Label("Edit Profile", systemImage: "person.crop.circle")
                        }
                        Button { showApplyProfile = true } label: {
                            Label("Application Details", systemImage: "person.text.rectangle")
                        }
                        Button { showSponsorRegister = true } label: {
                            Label("Sponsor Register", systemImage: "checkmark.shield")
                        }
                        Button { showPipelineStatus = true } label: {
                            Label("Scraper Status", systemImage: "gearshape.arrow.triangle.2.circlepath")
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
                // The countdown to 1 February sits beside the large title; the plain title still
                // shows once the list scrolls
                ToolbarItem(placement: .largeTitle) {
                    HStack(alignment: .center, spacing: 12) {
                        Text(pageTitle)
                            .font(.largeTitle.bold())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer(minLength: 0)
                        DeadlineTiles()
                    }
                }
            }
        }
        .task { await vm.loadAll() }
        .sheet(isPresented: $showManageSheets) {
            ManageSheetsView(vm: vm)
        }
        .sheet(isPresented: $showProfileEditor) {
            CVProfileEditorView(profileKey: vm.selectedProfile)
        }
        .sheet(isPresented: $showApplyProfile) {
            ApplyProfileView(profileKey: vm.selectedProfile)
        }
        .sheet(isPresented: $showBulletSuggester) {
            BulletSuggesterView(profile: vm.selectedProfile)
        }
        .sheet(isPresented: $showAddJob) {
            AddJobView(addedStore: vm.addedJobsStore, applicationsStore: vm.applicationsStore,
                       starredStore: vm.starredStore, profile: vm.selectedProfile, region: vm.region)
        }
        .sheet(isPresented: $showFeatureChats) {
            FeatureChatsListView(store: vm.chatStore, profile: vm.selectedProfile)
        }
        .sheet(isPresented: $showSponsorRegister) {
            SponsorRegisterView()
        }
        .sheet(isPresented: $showPipelineStatus) {
            PipelineStatusView()
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

    @ViewBuilder
    private func regionPage(_ model: RegionJobsModel) -> some View {
        let filtered = vm.filteredJobs(in: model)
        let added = addedJobs(in: model.region)
        Group {
            if model.isLoading && model.jobs.isEmpty && added.isEmpty {
                ProgressView("Loading jobs…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.errorMessage, added.isEmpty {
                ContentUnavailableView(
                    "Failed to load",
                    systemImage: "wifi.exclamationmark",
                    description: Text(error)
                )
            } else if vm.showStarredOnly && filtered.isEmpty {
                ContentUnavailableView(
                    "No starred jobs",
                    systemImage: "star",
                    description: Text("Swipe right on a job to star it")
                )
            } else if !model.isLoading && model.jobs.isEmpty && added.isEmpty {
                ContentUnavailableView(
                    "No jobs yet",
                    systemImage: "tray",
                    description: Text(model.region == "ww"
                                      ? "No remote roles saved yet. The nightly run adds them."
                                      : "Nothing has been scraped for \(model.region == "us" ? "the USA" : "the UK") yet")
                )
            } else {
                List {
                    if !added.isEmpty {
                        Section {
                            ForEach(added) { item in
                                NavigationLink(destination: JobDetailView(job: item.job, sheetName: nil, starredStore: vm.starredStore, applicationsStore: vm.applicationsStore, profile: vm.selectedProfile, region: item.region)) {
                                    JobRowView(job: item.job, sheetName: nil, starredStore: vm.starredStore, isApplied: false, region: item.region)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { vm.addedJobsStore.remove(item.id) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        } header: {
                            Text("Added by you")
                        }
                    }
                    Section {
                        ForEach(filtered) { job in
                            NavigationLink(destination: JobDetailView(job: job, sheetName: model.sheetName, starredStore: vm.starredStore, applicationsStore: vm.applicationsStore, profile: vm.selectedProfile, region: model.region)) {
                                JobRowView(job: job, sheetName: model.sheetName, starredStore: vm.starredStore, isApplied: vm.applicationsStore.isApplied(job.jobId), region: model.region)
                            }
                        }
                    } header: {
                        if !added.isEmpty && !filtered.isEmpty { Text("From the feed") }
                    }
                }
                .listStyle(.plain)
                .refreshable { await model.load() }
            }
        }
    }

    /// Jobs added by hand for this market and not yet applied to, matching the search; hidden
    /// while only starred jobs show
    private func addedJobs(in region: String) -> [AddedJob] {
        guard !vm.showStarredOnly else { return [] }
        let query = vm.searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return vm.addedJobsStore.jobs(in: region).filter { item in
            !vm.applicationsStore.isApplied(item.id)
                && (query.isEmpty || item.job.title.lowercased().contains(query) || item.job.company.lowercased().contains(query))
        }
    }

    private var pageTitle: String {
        vm.showStarredOnly ? "\(vm.filteredJobs.count) Starred"
            : vm.sortMode == .visa ? "\(vm.filteredJobs.count) Visa jobs"
            : "\(vm.filteredJobs.count) Jobs"
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

// MARK: - Market tabs (shared with FeedView)

/// Underline tabs in the X / Instagram style: full-width labels with a sliding ink bar.
/// The pager swipe and the tab taps both drive the same `region` binding.
struct MarketTabs: View {
    @Binding var region: String
    @Namespace private var ns

    private let options: [(tag: String, label: String)] = [("uk", "UK"), ("us", "USA"), ("ww", "Remote")]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(options, id: \.tag) { opt in
                    Button {
                        region = opt.tag
                    } label: {
                        VStack(spacing: 8) {
                            Text(opt.label)
                                .font(.system(size: 15, weight: region == opt.tag ? .semibold : .regular))
                                .foregroundColor(region == opt.tag ? .primary : .secondary)
                            ZStack {
                                Color.clear.frame(height: 3)
                                if region == opt.tag {
                                    Capsule()
                                        .fill(Color.primary)
                                        .frame(width: 52, height: 3)
                                        .matchedGeometryEffect(id: "ink", in: ns)
                                }
                            }
                        }
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
        }
        .background(.bar)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: region)
        .sensoryFeedback(.selection, trigger: region)
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
