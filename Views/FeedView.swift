import SwiftUI

// MARK: - Live feed — pure scrape on demand, no AI scoring, no sheets

private struct FeedResponse: Decodable {
    let jobs: [Job]
    let searches: Int?
    let failures: Int?
}

private enum FeedService {
    static func fetch(profile: String, region: String) async throws -> FeedResponse {
        guard var comps = URLComponents(string: "https://job-worker.pranavrokade.workers.dev/api/feed") else {
            throw URLError(.badURL)
        }
        comps.queryItems = [.init(name: "profile", value: profile), .init(name: "region", value: region)]
        guard let url = comps.url else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw NSError(domain: "Feed", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: msg ?? "Feed failed (\(http.statusCode))"])
        }
        return try JSONDecoder().decode(FeedResponse.self, from: data)
    }
}

/// Job ids already shown in the feed, so a refresh can badge what's genuinely new.
private enum FeedSeenStore {
    private static func key(_ profile: String) -> String { "feedSeen_\(profile)" }

    static func load(profile: String) -> Set<Int> {
        Set(UserDefaults.standard.array(forKey: key(profile)) as? [Int] ?? [])
    }

    static func save(_ ids: Set<Int>, profile: String) {
        // cap so UserDefaults doesn't grow forever
        UserDefaults.standard.set(Array(ids).suffix(3000).map { $0 }, forKey: key(profile))
    }
}

struct FeedView: View {
    @ObservedObject var starredStore: StarredJobsStore
    @ObservedObject var applicationsStore: ApplicationsStore
    let profile: String
    @State var region: String

    @State private var jobs: [Job] = []
    @State private var newIds: Set<Int> = []
    @State private var seen: Set<Int> = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var failures = 0
    @State private var searches = 0
    @State private var loadedOnce = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && jobs.isEmpty {
                    ProgressView("Scraping LinkedIn…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error, jobs.isEmpty {
                    ContentUnavailableView("Feed unavailable", systemImage: "wifi.exclamationmark", description: Text(error))
                } else if jobs.isEmpty {
                    ContentUnavailableView("Nothing fresh", systemImage: "antenna.radiowaves.left.and.right",
                                           description: Text("Pull to refresh"))
                } else {
                    List(jobs) { job in
                        NavigationLink {
                            JobDetailView(job: job, sheetName: nil, starredStore: starredStore,
                                          applicationsStore: applicationsStore, profile: profile, region: region)
                        } label: {
                            FeedRow(job: job,
                                    isNew: newIds.contains(job.jobId),
                                    isApplied: applicationsStore.isApplied(job.jobId))
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .navigationTitle(jobs.isEmpty ? "Live Feed" : "\(jobs.count) Fresh Jobs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button {
                            Task { await refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .refreshable { await refresh() }
            .task {
                guard !loadedOnce else { return }
                loadedOnce = true
                seen = FeedSeenStore.load(profile: profile)
                await refresh()
            }
            .onChange(of: region) { _ in
                jobs = []
                newIds = []
                Task { await refresh() }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Picker("Region", selection: $region) {
                Text("UK").tag("uk")
                Text("USA").tag("us")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            HStack {
                if !newIds.isEmpty {
                    Text("\(newIds.count) new since last refresh")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
                Spacer()
                if failures > 0 {
                    Text("\(failures)/\(searches) searches rate-limited")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            if let error, !jobs.isEmpty {
                Text(error).font(.caption2).foregroundColor(.red).padding(.horizontal)
            }
            Divider().padding(.top, 4)
        }
        .background(.bar)
    }

    private func refresh() async {
        isLoading = true
        error = nil
        do {
            let resp = try await FeedService.fetch(profile: profile, region: region)
            let ids = Set(resp.jobs.map(\.jobId))
            // First ever load has no baseline — don't badge the whole list as new
            newIds = seen.isEmpty ? [] : ids.subtracting(seen)
            seen.formUnion(ids)
            FeedSeenStore.save(seen, profile: profile)
            jobs = resp.jobs
            failures = resp.failures ?? 0
            searches = resp.searches ?? 0
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

private struct FeedRow: View {
    let job: Job
    let isNew: Bool
    let isApplied: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(job.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                if isNew {
                    Text("NEW")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.18))
                        .foregroundColor(.green)
                        .clipShape(Capsule())
                }
            }
            HStack(spacing: 4) {
                Text(job.company)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if isApplied {
                    Text("APPLIED")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                }
            }
            Text(job.location)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text(job.age)
                .font(.system(size: 11, weight: isNew ? .semibold : .regular))
                .foregroundColor(isNew ? .green : Color(.tertiaryLabel))
        }
        .padding(.vertical, 3)
    }
}
