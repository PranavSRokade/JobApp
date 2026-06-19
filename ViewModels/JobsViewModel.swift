import Foundation
import Combine

@MainActor
final class JobsViewModel: ObservableObject {
    @Published var jobs: [Job] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var sheetName: String?
    @Published var availableSheets: [String] = []
    @Published var selectedSheet: String? = nil {
        didSet { Task { await load() } }
    }
    @Published var selectedProfile: String = "spencer" {
        didSet {
            selectedSheet = nil
            starredStore = StarredJobsStore(profile: selectedProfile)
            Task { await load() }
        }
    }
    @Published var starredStore: StarredJobsStore = StarredJobsStore(profile: "spencer")
    @Published var showStarredOnly = false
    @Published var searchText = ""

    var filteredJobs: [Job] {
        let base = searchText.isEmpty ? jobs : jobs.filter {
            let q = searchText.lowercased()
            return $0.title.lowercased().contains(q) ||
                   $0.company.lowercased().contains(q) ||
                   $0.location.lowercased().contains(q)
        }
        if showStarredOnly {
            return base.filter { starredStore.isStarred($0.jobId) }
        }
        // Starred float to top, rest sorted by rank
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

    func load(silent: Bool = false) async {
        if !silent { isLoading = true }
        errorMessage = nil
        do {
            let response = try await JobsService.fetchJobs(profile: selectedProfile, sheet: selectedSheet)
            jobs = response.jobs.sorted { $0.rank > $1.rank }
            sheetName = response.sheet
            availableSheets = response.sheets
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
