import SwiftUI
import UserNotifications

@main
struct JobTrackerApp: App {
    // One view model for the whole app: the tabs share the same stores, so starring,
    // applying, or changing filters on one tab is instantly reflected on the others.
    @StateObject private var vm = JobsViewModel()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var tab = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                JobsListView(vm: vm)
                    .tabItem { Label("Jobs", systemImage: "list.bullet") }
                    .tag(0)
                FeedView(starredStore: vm.starredStore,
                         applicationsStore: vm.applicationsStore,
                         profile: vm.selectedProfile,
                         region: vm.region)
                    .tabItem { Label("Feed", systemImage: "dot.radiowaves.left.and.right") }
                    .tag(1)
                ApplicationsView(store: vm.applicationsStore,
                                 starredStore: vm.starredStore,
                                 profile: vm.selectedProfile)
                    .tabItem { Label("Applied", systemImage: "paperplane") }
                    .tag(2)
            }
            // A tapped starred-job reminder opens the starred list on the Jobs tab
            .onReceive(NotificationCenter.default.publisher(for: AppDelegate.openStarred)) { _ in
                tab = 0
                vm.showStarredOnly = true
            }
            .task { DeadlineBadgeCleanup.runOnce() }
            // JobFill's Mark applied adds to the list from Safari, so reload it whenever the app comes back
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await vm.applicationsStore.refresh() }
            }
        }
    }
}

/// Receives taps on starred-job reminders and lets them show while the app is open
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let openStarred = Notification.Name("openStarredFromReminder")

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.notification.request.content.userInfo[StarReminders.jobIdKey] != nil else { return }
        await MainActor.run { NotificationCenter.default.post(name: Self.openStarred, object: nil) }
    }
}
