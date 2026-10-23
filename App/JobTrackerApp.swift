import SwiftUI

@main
struct JobTrackerApp: App {
    // One view model for the whole app: the tabs share the same stores, so starring,
    // applying, or changing filters on one tab is instantly reflected on the others.
    @StateObject private var vm = JobsViewModel()

    var body: some Scene {
        WindowGroup {
            TabView {
                JobsListView(vm: vm)
                    .tabItem { Label("Jobs", systemImage: "list.bullet") }
                FeedView(starredStore: vm.starredStore,
                         applicationsStore: vm.applicationsStore,
                         profile: vm.selectedProfile,
                         region: vm.region)
                    .tabItem { Label("Feed", systemImage: "dot.radiowaves.left.and.right") }
                ApplicationsView(store: vm.applicationsStore,
                                 starredStore: vm.starredStore,
                                 profile: vm.selectedProfile)
                    .tabItem { Label("Applied", systemImage: "paperplane") }
            }
        }
    }
}
