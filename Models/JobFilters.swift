import Foundation
import Combine

struct JobFilters: Codable {
    var hideOver100: Bool = false
    var excludedCompanies: [String] = []
    var allowedTitleKeywords: [String] = []
    var blockedTitleKeywords: [String] = []

    // Only soft filters count toward "is default" — keyword arrays are always preserved
    var isDefault: Bool {
        !hideOver100 && excludedCompanies.isEmpty
    }
}

// Default keyword arrays sourced from job-tracker/src/config/profiles.ts
private let defaultAllowed: [String: [String]] = [
    "spencer": ["react native", "mobile engineer", "mobile developer", "ios", "android",
                "react-native", "software engineer", "frontend developer"],
    "gf":      ["assistant psychologist", "psychology", "mental health",
                "clinical psychology", "behaviour support"],
]

private let defaultBlocked: [String: [String]] = [
    "spencer": ["backend", "back end", "platform", "devops", "data", "python",
                "java backend", "principal", "founding", "lead", "cyber",
                "research", "physics", "payments", "ruby", "angular", "c++",
                "AWS", "GO", "security"],
    "gf":      ["nursing", "nurse support worker", "clinical advisor"],
]

final class JobFiltersStore: ObservableObject {
    @Published var filters: JobFilters {
        didSet {
            guard !_isSyncing else { return }
            save()
            scheduleServerPush()
        }
    }
    private let key: String
    private let profile: String
    private var _isSyncing = false
    private var pushTask: Task<Void, Never>?

    init(profile: String) {
        self.profile = profile
        key = "jobFilters_\(profile)"
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(JobFilters.self, from: data) {
            filters = saved
        } else {
            var f = JobFilters()
            f.allowedTitleKeywords = defaultAllowed[profile] ?? []
            f.blockedTitleKeywords = defaultBlocked[profile] ?? []
            filters = f
        }
        Task { await fetchFromServer() }
    }

    // Pull latest from KV — overwrites local (server is source of truth)
    // Falls back to hardcoded defaults if KV arrays are empty (e.g. after accidental reset)
    @MainActor
    func fetchFromServer() async {
        guard let remote = try? await CVProfileService.fetchTitleFilters(for: profile) else { return }
        let restoredAllowed  = remote.allowed.isEmpty  ? (defaultAllowed[profile]  ?? []) : remote.allowed
        let restoredBlocked  = remote.blocked.isEmpty  ? (defaultBlocked[profile]  ?? []) : remote.blocked
        _isSyncing = true
        filters.allowedTitleKeywords = restoredAllowed
        filters.blockedTitleKeywords = restoredBlocked
        filters.excludedCompanies    = remote.blockedCompanies
        _isSyncing = false
        save()
        // Re-push if we had to restore defaults so KV is correct
        if remote.allowed.isEmpty || remote.blocked.isEmpty {
            let f = CVProfileService.TitleFilters(
                allowed: restoredAllowed,
                blocked: restoredBlocked,
                blockedCompanies: remote.blockedCompanies
            )
            try? await CVProfileService.saveTitleFilters(f, for: profile)
        }
    }

    private func scheduleServerPush() {
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s debounce
            guard !Task.isCancelled else { return }
            let f = CVProfileService.TitleFilters(
                allowed: filters.allowedTitleKeywords,
                blocked: filters.blockedTitleKeywords,
                blockedCompanies: filters.excludedCompanies
            )
            try? await CVProfileService.saveTitleFilters(f, for: profile)
        }
    }

    func apply(to jobs: [Job]) -> [Job] {
        jobs.filter { job in
            if filters.hideOver100 && job.over100 { return false }
            let titleLower = job.title.lowercased()
            if !filters.allowedTitleKeywords.isEmpty {
                if !filters.allowedTitleKeywords.contains(where: { titleLower.contains($0.lowercased()) }) { return false }
            }
            if !filters.blockedTitleKeywords.isEmpty {
                if filters.blockedTitleKeywords.contains(where: { titleLower.contains($0.lowercased()) }) { return false }
            }
            if !filters.excludedCompanies.isEmpty {
                let companyLower = job.company.lowercased()
                if filters.excludedCompanies.contains(where: { companyLower.contains($0.lowercased()) }) { return false }
            }
            return true
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(filters) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
