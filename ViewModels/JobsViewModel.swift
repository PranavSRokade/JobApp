import Foundation
import Combine

// Change this one string to switch profiles across the whole app
private let activeProfile = "spencer"

/// One market's sheet-backed job list. UK and US each get their own instance so switching
/// tabs never reloads, and scroll position / data survive swiping back and forth.
@MainActor
final class RegionJobsModel: ObservableObject {
    let region: String
    private let profile: String

    @Published var jobs: [Job] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var sheetName: String?
    @Published var availableSheets: [String] = []
    @Published var selectedSheet: String? = nil {
        didSet { reload() }
    }

    /// Lets the view model record jobId → sheet for the starred-sheets indicator
    var onLoaded: ((String?, [Job]) -> Void)?
    private var loadTask: Task<Void, Never>?

    init(region: String, profile: String) {
        self.region = region
        self.profile = profile
    }

    // One fetch in flight at a time: switching sheets quickly must not let an older
    // response land after a newer one.
    func reload() {
        loadTask?.cancel()
        loadTask = Task { await load() }
    }

    func load(silent: Bool = false) async {
        if !silent { isLoading = true }
        errorMessage = nil
        do {
            let response = try await JobsService.fetchJobs(profile: profile, sheet: selectedSheet, region: region)
            guard !Task.isCancelled else { return }
            jobs = response.jobs.sorted { $0.rank > $1.rank }
            sheetName = response.sheet
            availableSheets = response.sheets
            onLoaded?(response.sheet, jobs)
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

@MainActor
final class JobsViewModel: ObservableObject {
    // Each market is a real, independent list; both load in parallel at launch.
    let uk: RegionJobsModel
    let us: RegionJobsModel

    // Which market tab is showing. Remembered per profile.
    @Published var region: String = UserDefaults.standard.string(forKey: "region_\(activeProfile)") ?? "uk" {
        didSet {
            guard oldValue != region else { return }
            UserDefaults.standard.set(region, forKey: "region_\(activeProfile)")
        }
    }
    var active: RegionJobsModel { region == "us" ? us : uk }

    let selectedProfile = activeProfile
    @Published var starredStore: StarredJobsStore = StarredJobsStore(profile: activeProfile)
    @Published var filtersStore: JobFiltersStore = JobFiltersStore(profile: activeProfile) {
        didSet { subscribeToFilters() }
    }
    let chatStore: FeatureChatStore = FeatureChatStore(profile: activeProfile)
    // Jobs you've applied to — KV-backed, independent of the loaded sheet
    let applicationsStore: ApplicationsStore = ApplicationsStore(profile: activeProfile)

    private var cancellables: Set<AnyCancellable> = []
    private var filtersCancellable: AnyCancellable?
    private var starsCancellable: AnyCancellable?
    @Published var sheetsWithStars: Set<String> = []
    private var jobSheetMap: [Int: String] = [:]
    @Published var showStarredOnly = false
    @Published var searchText = ""

    // MARK: Active-market forwarders — keep existing call sites (detail, manage sheets) working

    var jobs: [Job] { active.jobs }
    var isLoading: Bool { active.isLoading }
    var errorMessage: String? { active.errorMessage }
    var sheetName: String? { active.sheetName }
    var availableSheets: [String] { active.availableSheets }
    var selectedSheet: String? {
        get { active.selectedSheet }
        set { active.selectedSheet = newValue }
    }

    var filteredJobs: [Job] { filteredJobs(in: active) }

    func filteredJobs(in model: RegionJobsModel) -> [Job] {
        var base = filtersStore.apply(to: model.jobs)
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            base = base.filter {
                $0.title.lowercased().contains(q) ||
                $0.company.lowercased().contains(q) ||
                $0.location.lowercased().contains(q)
            }
        }
        if showStarredOnly {
            // Merge snapshot-starred jobs (e.g. from the feed) that aren't in this sheet tab
            let tabIds = Set(model.jobs.map(\.jobId))
            let inTab = base.filter { starredStore.isStarred($0.jobId) }
            var extra = starredStore.starredJobs(region: model.region).filter { !tabIds.contains($0.jobId) }
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                extra = extra.filter {
                    $0.title.lowercased().contains(q) ||
                    $0.company.lowercased().contains(q) ||
                    $0.location.lowercased().contains(q)
                }
            }
            return inTab + extra.sorted { $0.rank > $1.rank }
        }
        let starred = base.filter { starredStore.isStarred($0.jobId) }
        let rest = base.filter { !starredStore.isStarred($0.jobId) }
        return starred + rest
    }

    func loadAll() async {
        async let ukLoad: Void = uk.load()
        async let usLoad: Void = us.load()
        _ = await (ukLoad, usLoad)
    }

    func deleteSheet(_ sheet: String) async {
        await bulkDeleteSheets([sheet])
    }

    func bulkDeleteSheets(_ sheets: Set<String>) async {
        let model = active
        let previousJobIds = Set(model.jobs.map(\.jobId))

        model.availableSheets.removeAll { sheets.contains($0) }
        if let current = model.selectedSheet, sheets.contains(current) {
            model.selectedSheet = nil
            model.sheetName = model.availableSheets.first
        }

        do {
            try await JobsService.deleteSheets(profile: selectedProfile, sheets: sheets)
        } catch {
            model.errorMessage = error.localizedDescription
        }

        await model.load(silent: true)
        // Stars deliberately survive tab deletion now — they're snapshot bookmarks,
        // visible under Show Starred regardless of which tabs exist.
        _ = previousJobIds
    }

    init() {
        uk = RegionJobsModel(region: "uk", profile: activeProfile)
        us = RegionJobsModel(region: "us", profile: activeProfile)
        loadJobSheetMap()

        let record: (String?, [Job]) -> Void = { [weak self] sheet, jobs in
            self?.recordLoaded(sheet: sheet, jobs: jobs)
        }
        uk.onLoaded = record
        us.onLoaded = record

        // Re-render when either market or the applications tracker changes
        uk.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        us.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        applicationsStore.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)

        subscribeToFilters()
        subscribeToStars()
    }

    private func subscribeToFilters() {
        filtersCancellable = filtersStore.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    private func subscribeToStars() {
        starsCancellable = starredStore.$starredIds.sink { [weak self] ids in
            guard let self else { return }
            self.sheetsWithStars = Set(ids.compactMap { self.jobSheetMap[$0] })
        }
    }

    private func recordLoaded(sheet: String?, jobs: [Job]) {
        guard let name = sheet else { return }
        for job in jobs { jobSheetMap[job.jobId] = name }
        saveJobSheetMap()
        sheetsWithStars = Set(starredStore.starredIds.compactMap { jobSheetMap[$0] })
    }

    private func loadJobSheetMap() {
        let raw = UserDefaults.standard.dictionary(forKey: "jobSheetMap_\(selectedProfile)") as? [String: String] ?? [:]
        jobSheetMap = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in Int(k).map { ($0, v) } })
        sheetsWithStars = Set(starredStore.starredIds.compactMap { jobSheetMap[$0] })
    }

    private func saveJobSheetMap() {
        let raw = Dictionary(uniqueKeysWithValues: jobSheetMap.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(raw, forKey: "jobSheetMap_\(selectedProfile)")
    }
}
