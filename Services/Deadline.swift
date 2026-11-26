import SwiftUI
import UserNotifications

/// The countdown to 1 February 2027, midnight UK time, shown live on the Jobs page.
enum Deadline {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .current
        return calendar
    }()
    static let date: Date = calendar.date(from: DateComponents(year: 2027, month: 2, day: 1)) ?? .distantFuture

    /// Calendar days left, counting today: 1 on 31 January, 0 from 1 February on
    static func daysLeft(from now: Date = .now) -> Int {
        max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: date).day ?? 0)
    }

    /// Exact time left, for the ticking banner; all zero from midnight on 1 February
    static func remaining(from now: Date = .now) -> (days: Int, hours: Int, minutes: Int, seconds: Int) {
        let total = max(0, Int(date.timeIntervalSince(now)))
        return (total / 86_400, total % 86_400 / 3_600, total % 3_600 / 60, total % 60)
    }
}

/// The icon badge countdown was dropped on 2026-11-26. This clears the badge and the midnight
/// updates the one build that had it queued, once per install.
enum DeadlineBadgeCleanup {
    private static let doneKey = "deadlineBadgeCleared"

    static func runOnce() {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("deadline-badge-") })
        }
        center.setBadgeCount(0) { _ in }
        UserDefaults.standard.set(true, forKey: doneKey)
    }
}

/// Orange inside 30 days, red inside 14
private func deadlineTint(_ now: Date) -> Color {
    let days = Deadline.daysLeft(from: now)
    return days <= 14 ? .red : days <= 30 ? .orange : .accentColor
}

private func spokenLeft(_ now: Date) -> String {
    let left = Deadline.remaining(from: now)
    return "\(left.days) days, \(left.hours) hours and \(left.minutes) minutes until 1 February"
}

/// Days, hours, minutes and seconds as four small tiles beside the Jobs page's large title
struct DeadlineTiles: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = Deadline.remaining(from: context.date)
            let tint = deadlineTint(context.date)
            HStack(spacing: 4) {
                tile(left.days, "d", tint)
                tile(left.hours, "h", .primary)
                tile(left.minutes, "m", .primary)
                tile(left.seconds, "s", .primary)
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLeft(context.date))
        }
    }

    private func tile(_ value: Int, _ unit: String, _ color: Color) -> some View {
        VStack(spacing: -3) {
            Text(String(format: "%02d", value))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .contentTransition(.numericText(countsDown: true))
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 36, height: 34) // the large-title row clips anything taller
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}
