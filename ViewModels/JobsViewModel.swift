import Foundation
import Combine

// Change this one string to switch profiles across the whole app
private let activeProfile = "spencer"

@MainActor
final class JobsViewModel: ObservableObject {
    @Published var jobs: [Job] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var sheetName: String?
    @Published var availableSheets: [String] = []
    @Published var selectedSheet: String? = nil {
        didSet { reload() }
    }
    let selectedProfile = activeProfile
    // "uk" or "us" — which market's sheet tabs to show. Remembered per profile.
    @Published var region: String = UserDefaults.standard.string(forKey: "region_\(activeProfile)") ?? "uk" {
        didSet {
            guard oldValue != region else { return }
            UserDefaults.standard.set(region, forKey: "region_\(activeProfile)")
            // Tabs differ per region: clear the old list so the spinner shows, then fetch this region's latest.
            jobs = []
            sheetName = nil
            availableSheets = []
            selectedSheet = nil // didSet → reload() (cancels any fetch still in flight)
        }
    }
    @Published var starredStore: StarredJobsStore = StarredJobsStore(profile: activeProfile)
    @Published var filtersStore: JobFiltersStore = JobFiltersStore(profile: activeProfile) {
        didSet { subscribeToFilters() }
    }
    let chatStore: FeatureChatStore = FeatureChatStore(profile: activeProfile)
    // Jobs you've applied to — KV-backed, independent of the loaded sheet
    let applicationsStore: ApplicationsStore = ApplicationsStore(profile: activeProfile)
    private var filtersCancellable: AnyCancellable?
    private var applicationsCancellable: AnyCancellable?
    private var starsCancellable: AnyCancellable?
    private var loadTask: Task<Void, Never>?
    @Published var sheetsWithStars: Set<String> = []
    private var jobSheetMap: [Int: String] = [:]
    @Published var showStarredOnly = false
    @Published var searchText = ""

    var filteredJobs: [Job] {
        var base = filtersStore.apply(to: jobs)
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            base = base.filter {
                $0.title.lowercased().contains(q) ||
                $0.company.lowercased().contains(q) ||
                $0.location.lowercased().contains(q)
            }
        }
        if showStarredOnly {
            return base.filter { starredStore.isStarred($0.jobId) }
        }
        let starred = base.filter { starredStore.isStarred($0.jobId) }
        let rest = base.filter { !starredStore.isStarred($0.jobId) }
        return starred + rest
    }

    func deleteSheet(_ sheet: String) async {
        await bulkDeleteSheets([sheet])
    }

    func bulkDeleteSheets(_ sheets: Set<String>) async {
        let previousJobIds = Set(jobs.map(\.jobId))

        availableSheets.removeAll { sheets.contains($0) }
        if let current = selectedSheet, sheets.contains(current) {
            selectedSheet = nil
            sheetName = availableSheets.first
        }

        do {
            try await JobsService.deleteSheets(profile: selectedProfile, sheets: sheets)
        } catch {
            errorMessage = error.localizedDescription
        }

        await load(silent: true)

        // Clear stars for jobs that no longer exist after deletion
        let remainingJobIds = Set(jobs.map(\.jobId))
        let removedIds = previousJobIds.subtracting(remainingJobIds)
        if !removedIds.isEmpty {
            starredStore.clearStars(forJobIds: Array(removedIds))
        }
    }

    init() {
        loadJobSheetMap()
        subscribeToFilters()
        subscribeToStars()
        subscribeToApplications()
    }

    private func subscribeToFilters() {
        filtersCancellable = filtersStore.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    // Rows show an "Applied" chip, so the list must re-render when applications change
    private func subscribeToApplications() {
        applicationsCancellable = applicationsStore.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    private func subscribeToStars() {
        starsCancellable = starredStore.$starredIds.sink { [weak self] ids in
            guard let self else { return }
            self.sheetsWithStars = Set(ids.compactMap { self.jobSheetMap[$0] })
        }
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

    // One fetch in flight at a time: switching region/sheet quickly must not let an older
    // response land after a newer one.
    private func reload() {
        loadTask?.cancel()
        loadTask = Task { await load() }
    }

    func load(silent: Bool = false) async {
        if !silent { isLoading = true }
        errorMessage = nil
        do {
            let response = try await JobsService.fetchJobs(profile: selectedProfile, sheet: selectedSheet, region: region)
            guard !Task.isCancelled else { return }
            jobs = response.jobs.sorted { $0.rank > $1.rank }
            sheetName = response.sheet
            availableSheets = response.sheets
            if let name = response.sheet {
                for job in jobs { jobSheetMap[job.jobId] = name }
                saveJobSheetMap()
                sheetsWithStars = Set(starredStore.starredIds.compactMap { jobSheetMap[$0] })
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
