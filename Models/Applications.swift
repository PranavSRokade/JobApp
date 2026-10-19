import Foundation
import Combine

// MARK: - Models

/// A pipeline stage ("Applied", "First interview", …). User-editable; order = display order.
struct ApplicationStage: Codable, Identifiable, Equatable {
    var id: String
    var name: String
}

struct StatusChange: Codable, Identifiable {
    var id: UUID = UUID()
    var stageId: String
    var at: Date

    private enum CodingKeys: String, CodingKey { case stageId, at }
}

/// A job you applied to. Holds a snapshot of the job so it stays viewable even after the sheet
/// tab it came from is deleted — the tracker is independent of whatever sheet is loaded.
struct Application: Codable, Identifiable {
    var job: Job
    var region: String
    var sheet: String?
    var appliedAt: Date
    var stageId: String
    var notes: String
    var applicantsAtFetch: String?   // LinkedIn caption when the job was scraped
    var applicantsAtApply: String?   // LinkedIn caption fetched when you marked it applied
    var history: [StatusChange]

    var id: Int { job.jobId }

    var daysSinceApplied: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: appliedAt), to: cal.startOfDay(for: Date())).day ?? 0
    }

    var appliedAgoText: String {
        switch daysSinceApplied {
        case 0: return "Applied today"
        case 1: return "Applied yesterday"
        default: return "Applied \(daysSinceApplied) days ago"
        }
    }

    /// "31 → 67 applicants", "31 applicants", or nil
    var applicantsSummary: String? {
        func num(_ s: String?) -> String? {
            guard let s, !s.isEmpty else { return nil }
            return s.replacingOccurrences(of: " applicants", with: "").replacingOccurrences(of: " applicant", with: "")
        }
        switch (num(applicantsAtFetch), num(applicantsAtApply)) {
        case let (a?, b?) where a != b: return "\(a) → \(b) applicants"
        case let (a?, _): return "\(a) applicants"
        case let (nil, b?): return "\(b) applicants when applied"
        default: return nil
        }
    }
}

// MARK: - Store

/// Source of truth is KV via the worker (survives reinstalls); UserDefaults is only a cache so the
/// list opens instantly. Whole-document writes, debounced.
@MainActor
final class ApplicationsStore: ObservableObject {
    @Published private(set) var stages: [ApplicationStage] = ApplicationsStore.defaultStages
    @Published private(set) var applications: [Application] = []
    @Published private(set) var isLoaded = false
    @Published var lastError: String?

    static let defaultStages: [ApplicationStage] = [
        .init(id: "applied", name: "Applied"),
        .init(id: "screening", name: "Screening call"),
        .init(id: "interview1", name: "First interview"),
        .init(id: "technical", name: "Technical interview"),
        .init(id: "final", name: "Final interview"),
        .init(id: "offer", name: "Offer"),
        .init(id: "rejected", name: "Rejected"),
        .init(id: "withdrawn", name: "Withdrawn"),
    ]

    private let profile: String
    private let endpoint = "https://job-worker.pranavrokade.workers.dev/api/applications"
    private var saveTask: Task<Void, Never>?
    private var hasLocalChanges = false

    private struct Blob: Codable {
        var stages: [ApplicationStage]
        var applications: [Application]
    }

    init(profile: String) {
        self.profile = profile
        loadCache()
        Task { await refresh() }
    }

    // MARK: Queries

    func application(for jobId: Int) -> Application? { applications.first { $0.id == jobId } }
    func isApplied(_ jobId: Int) -> Bool { application(for: jobId) != nil }
    func stageName(_ id: String) -> String { stages.first { $0.id == id }?.name ?? id }
    func count(in stageId: String) -> Int { applications.filter { $0.stageId == stageId }.count }

    // MARK: Applications

    func markApplied(_ job: Job, region: String, sheet: String?) {
        guard !isApplied(job.jobId) else { return }
        let first = stages.first?.id ?? "applied"
        let now = Date()
        let app = Application(
            job: job, region: region, sheet: sheet, appliedAt: now, stageId: first, notes: "",
            applicantsAtFetch: job.applicantsText, applicantsAtApply: nil,
            history: [StatusChange(stageId: first, at: now)]
        )
        applications.insert(app, at: 0)
        persist()

        // How many had applied at the moment you did — fetched live from the posting
        Task { [weak self] in
            guard let self else { return }
            guard let current = try? await self.fetchApplicants(url: job.link), !current.isEmpty else { return }
            if let i = self.applications.firstIndex(where: { $0.id == job.jobId }) {
                self.applications[i].applicantsAtApply = current
                self.persist()
            }
        }
    }

    func unmark(_ jobId: Int) {
        applications.removeAll { $0.id == jobId }
        persist()
    }

    func setStage(_ jobId: Int, stageId: String) {
        guard let i = applications.firstIndex(where: { $0.id == jobId }), applications[i].stageId != stageId else { return }
        applications[i].stageId = stageId
        applications[i].history.append(StatusChange(stageId: stageId, at: Date()))
        persist()
    }

    func setNotes(_ jobId: Int, notes: String) {
        guard let i = applications.firstIndex(where: { $0.id == jobId }) else { return }
        applications[i].notes = notes
        persist()
    }

    // MARK: Stages

    func addStage(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var id = trimmed.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
        while stages.contains(where: { $0.id == id }) || id.isEmpty { id += "-\(Int.random(in: 10...99))" }
        stages.append(ApplicationStage(id: id, name: trimmed))
        persist()
    }

    func renameStage(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let i = stages.firstIndex(where: { $0.id == id }) else { return }
        stages[i].name = trimmed
        persist()
    }

    func moveStages(from source: IndexSet, to destination: Int) {
        stages.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    /// Applications in a deleted stage move to the first remaining stage.
    func deleteStage(_ id: String) {
        guard stages.count > 1, let fallback = stages.first(where: { $0.id != id })?.id else { return }
        for i in applications.indices where applications[i].stageId == id {
            applications[i].stageId = fallback
            applications[i].history.append(StatusChange(stageId: fallback, at: Date()))
        }
        stages.removeAll { $0.id == id }
        persist()
    }

    // MARK: Sync

    func refresh() async {
        guard let url = URL(string: "\(endpoint)?profile=\(profile)") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let blob = try Self.decoder.decode(Blob.self, from: data)
            // Don't clobber edits made while this request was in flight
            guard !hasLocalChanges else { isLoaded = true; return }
            stages = blob.stages.isEmpty ? Self.defaultStages : blob.stages
            applications = blob.applications
            saveCache()
        } catch {
            lastError = error.localizedDescription
        }
        isLoaded = true
    }

    private func persist() {
        hasLocalChanges = true
        saveCache()
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.push()
        }
    }

    private func push() async {
        guard let url = URL(string: "\(endpoint)?profile=\(profile)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? Self.encoder.encode(Blob(stages: stages, applications: applications))
        req.timeoutInterval = 30
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                hasLocalChanges = false
                lastError = nil
            } else {
                lastError = "Could not save applications to the server"
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func fetchApplicants(url: String) async throws -> String? {
        guard let endpoint = URL(string: "https://job-worker.pranavrokade.workers.dev/api/applicants") else { return nil }
        struct Body: Encodable { let url: String }
        struct Resp: Decodable { let applicants: String? }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(Body(url: url))
        req.timeoutInterval = 30
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(Resp.self, from: data).applicants
    }

    // MARK: Cache

    private var cacheKey: String { "applications_\(profile)" }

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let blob = try? Self.decoder.decode(Blob.self, from: data) else { return }
        stages = blob.stages.isEmpty ? Self.defaultStages : blob.stages
        applications = blob.applications
    }

    private func saveCache() {
        if let data = try? Self.encoder.encode(Blob(stages: stages, applications: applications)) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
