import Foundation
import Combine

/// A starred job is kept as a full snapshot, so stars work on feed jobs (which aren't in any
/// sheet tab) and survive tab deletion. "Show Starred" renders from these snapshots.
struct StarredSnapshot: Codable {
    let job: Job
    let region: String
}

final class StarredJobsStore: ObservableObject {
    @Published private(set) var starredIds: Set<Int> = []
    private var snapshots: [Int: StarredSnapshot] = [:]
    private let profile: String

    init(profile: String) {
        self.profile = profile
        load()
    }

    func toggle(_ job: Job, region: String) {
        if starredIds.contains(job.jobId) {
            starredIds.remove(job.jobId)
            snapshots.removeValue(forKey: job.jobId)
        } else {
            starredIds.insert(job.jobId)
            snapshots[job.jobId] = StarredSnapshot(job: job, region: region)
        }
        save()
    }

    func isStarred(_ jobId: Int) -> Bool {
        starredIds.contains(jobId)
    }

    /// All starred jobs for a market — including feed jobs that never reached a sheet tab.
    func starredJobs(region: String) -> [Job] {
        snapshots.values.filter { $0.region == region }.map(\.job)
    }

    private func idsKey() -> String { "starred_\(profile)" }
    private func snapshotsKey() -> String { "starredSnapshots_\(profile)" }

    private func load() {
        let stored = UserDefaults.standard.array(forKey: idsKey()) as? [Int] ?? []
        starredIds = Set(stored)
        if let data = UserDefaults.standard.data(forKey: snapshotsKey()),
           let decoded = try? JSONDecoder().decode([Int: StarredSnapshot].self, from: data) {
            snapshots = decoded
        }
    }

    private func save() {
        UserDefaults.standard.set(Array(starredIds), forKey: idsKey())
        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults.standard.set(data, forKey: snapshotsKey())
        }
    }
}
