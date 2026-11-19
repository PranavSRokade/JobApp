import Foundation
import UserNotifications
import Combine

/// A starred job is kept as a full snapshot, so stars work on feed jobs (which aren't in any
/// sheet tab) and survive tab deletion. "Show Starred" renders from these snapshots.
struct StarredSnapshot: Codable {
    let job: Job
    let region: String
    var starredAt: Date? = nil   // nil for stars saved before reminders existed (Nov 2026)
}

final class StarredJobsStore: ObservableObject {
    @Published private(set) var starredIds: Set<Int> = []
    private var snapshots: [Int: StarredSnapshot] = [:]
    private let profile: String

    init(profile: String) {
        self.profile = profile
        load()
    }

    /// `remind` is false when the job is already applied to, so starring it doesn't start reminders
    func toggle(_ job: Job, region: String, remind: Bool = true) {
        if starredIds.contains(job.jobId) {
            starredIds.remove(job.jobId)
            snapshots.removeValue(forKey: job.jobId)
            StarReminders.cancel(job.jobId)
        } else {
            let now = Date()
            starredIds.insert(job.jobId)
            snapshots[job.jobId] = StarredSnapshot(job: job, region: region, starredAt: now)
            if remind { StarReminders.schedule(job, starredAt: now) }
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

// MARK: - Reminders

/// Local notifications nudging you to apply to a starred job: at 9:00 and 18:00 over the two days
/// after starring it, four at most. Unstarring or marking it applied cancels the rest. Phone-only,
/// so they need no server and work on a free signing account.
enum StarReminders {
    static let jobIdKey = "starredJobId"
    private static let hours = [9, 18]
    private static let window: TimeInterval = 48 * 3600
    private static let maxReminders = 4

    static func schedule(_ job: Job, starredAt: Date) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            for (n, date) in slots(after: starredAt).enumerated() {
                let content = UNMutableNotificationContent()
                content.title = "Still starred: \(job.title)"
                content.body = n == 0
                    ? "\(job.company). Apply while it's fresh?"
                    : "\(job.company). You starred this \(ago(starredAt, to: date)). Apply or unstar it."
                content.sound = .default
                content.userInfo = [jobIdKey: job.jobId]
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                center.add(UNNotificationRequest(identifier: id(job.jobId, n), content: content, trigger: trigger))
            }
        }
    }

    static func cancel(_ jobId: Int) {
        let ids = (0..<maxReminders).map { id(jobId, $0) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// The 9:00 and 18:00 slots inside the window, skipping any less than an hour after starring
    static func slots(after start: Date, calendar: Calendar = .current) -> [Date] {
        var out: [Date] = []
        var day = calendar.startOfDay(for: start)
        while out.count < maxReminders, day < start.addingTimeInterval(window) {
            for h in hours {
                guard let d = calendar.date(bySettingHour: h, minute: 0, second: 0, of: day) else { continue }
                if d >= start.addingTimeInterval(3600), d <= start.addingTimeInterval(window), out.count < maxReminders { out.append(d) }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400)
        }
        return out
    }

    private static func id(_ jobId: Int, _ n: Int) -> String { "star-\(jobId)-\(n)" }

    private static func ago(_ from: Date, to: Date) -> String {
        let hours = Int(to.timeIntervalSince(from) / 3600)
        return hours < 24 ? "\(hours) hours ago" : "yesterday"
    }
}
