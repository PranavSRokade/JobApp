import Foundation
import Combine

final class StarredJobsStore: ObservableObject {
    @Published private(set) var starredIds: Set<Int> = []
    private let profile: String

    init(profile: String) {
        self.profile = profile
        load()
    }

    func toggle(_ jobId: Int) {
        if starredIds.contains(jobId) {
            starredIds.remove(jobId)
        } else {
            starredIds.insert(jobId)
        }
        save()
    }

    func isStarred(_ jobId: Int) -> Bool {
        starredIds.contains(jobId)
    }

    func clearStars(forJobIds ids: [Int]) {
        let toRemove = Set(ids)
        guard !starredIds.isDisjoint(with: toRemove) else { return }
        starredIds.subtract(toRemove)
        save()
    }

    private func key() -> String { "starred_\(profile)" }

    private func load() {
        let stored = UserDefaults.standard.array(forKey: key()) as? [Int] ?? []
        starredIds = Set(stored)
    }

    private func save() {
        UserDefaults.standard.set(Array(starredIds), forKey: key())
    }
}
