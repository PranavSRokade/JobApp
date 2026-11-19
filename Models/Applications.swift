import Foundation
import Combine
import SwiftUI // move(fromOffsets:toOffset:) for reordering stages

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

/// A PDF you sent with an application. The bytes live on the worker; this is what the list shows.
struct AttachedCV: Codable, Equatable {
    var name: String
    var uploadedAt: Date
    var bytes: Int
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
    var customCV: AttachedCV?        // the CV actually sent, uploaded from Files (PDF in the worker's KV)
    var shortlistChance: Int? = nil  // your 0–10 guess, asked right after applying; nil = skipped

    var id: Int { job.jobId }

    /// Added by hand from the Applied tab rather than from a scraped sheet
    var isCustom: Bool { region == ApplicationsStore.customRegion }

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

enum CVUploadError: LocalizedError {
    case tooLarge, rejected, missing
    var errorDescription: String? {
        switch self {
        case .tooLarge: return "That PDF is over 5 MB."
        case .rejected: return "The server didn't accept the file. Is it a PDF?"
        case .missing: return "No CV is saved for this application."
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
        StarReminders.cancel(job.jobId)

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

    func setShortlistChance(_ jobId: Int, _ chance: Int?) {
        guard let i = applications.firstIndex(where: { $0.id == jobId }) else { return }
        applications[i].shortlistChance = chance.map { min(10, max(0, $0)) }
        persist()
    }

    // MARK: Applications added by hand

    static let customRegion = "custom"

    /// A job applied to outside the scraped sheets. The worker keys uploaded CVs by a numeric job id of
    /// at most 12 digits; LinkedIn ids are 10 digits, so 9xx,xxx,xxx,xxx can never clash with one.
    func addCustom(title: String, company: String, link: String, location: String, jd: String?) -> Job {
        var id = 900_000_000_000 + Int(Date().timeIntervalSince1970)
        while isApplied(id) { id += 1 }
        let job = Job(
            rank: 0, title: title, company: company, jobId: id, link: link, over100: false, age: "",
            location: location, skills: 0, experience: 0, seniority: 0, locationFit: 0, companySize: 0,
            scoreSource: "", jd: jd, sponsorship: nil, salary: nil, visaNotes: nil, applicants: nil
        )
        let now = Date()
        let first = stages.first?.id ?? "applied"
        applications.insert(Application(
            job: job, region: Self.customRegion, sheet: nil, appliedAt: now, stageId: first, notes: "",
            applicantsAtFetch: nil, applicantsAtApply: nil, history: [StatusChange(stageId: first, at: now)]
        ), at: 0)
        persist()
        return job
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

    /// Drops one step a mis-tap added. The application moves to whatever stage is then last.
    func removeHistoryStep(_ jobId: Int, at index: Int) {
        guard let i = applications.firstIndex(where: { $0.id == jobId }),
              applications[i].history.count > 1, applications[i].history.indices.contains(index) else { return }
        applications[i].history.remove(at: index)
        applications[i].stageId = applications[i].history.last!.stageId
        persist()
    }

    // MARK: Progress

    /// Stages that end an application rather than move it forward. Stages are user-editable, so the
    /// built-in ids are matched and renamed or added ones are caught by name.
    func isTerminal(_ stageId: String) -> Bool {
        if stageId == "rejected" || stageId == "withdrawn" { return true }
        let name = stageName(stageId).lowercased()
        return name.hasPrefix("reject") || name.hasPrefix("withdr")
    }

    /// The furthest forward stage an application ever reached, by the order of the stages list
    func furthestStage(_ app: Application) -> ApplicationStage? {
        let progress = stages.filter { !isTerminal($0.id) }
        let reached = Set(app.history.map(\.stageId) + [app.stageId])
        return progress.last { reached.contains($0.id) } ?? progress.first
    }

    func setNotes(_ jobId: Int, notes: String) {
        guard let i = applications.firstIndex(where: { $0.id == jobId }) else { return }
        applications[i].notes = notes
        persist()
    }

    // MARK: Uploaded CVs

    private var cvEndpoint: String { "https://job-worker.pranavrokade.workers.dev/api/applications/cv" }

    func attachCV(_ jobId: Int, from fileURL: URL) async throws {
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
        try await attachCV(jobId, data: try Data(contentsOf: fileURL), name: fileURL.lastPathComponent)
    }

    /// Uploads a PDF as the CV sent with this application (a file from Files, or a generated quick CV)
    func attachCV(_ jobId: Int, data: Data, name: String) async throws {
        guard data.count <= 5 * 1024 * 1024 else { throw CVUploadError.tooLarge }
        guard let url = URL(string: "\(cvEndpoint)?profile=\(profile)&jobId=\(jobId)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/pdf", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        let (_, response) = try await URLSession.shared.upload(for: req, from: data)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CVUploadError.rejected }
        guard let i = applications.firstIndex(where: { $0.id == jobId }) else { return }
        applications[i].customCV = AttachedCV(name: name, uploadedAt: Date(), bytes: data.count)
        persist()
    }

    /// Downloads the uploaded PDF to a temporary file named after the original, for Quick Look
    func downloadCV(_ jobId: Int) async throws -> URL {
        guard let app = application(for: jobId), let cv = app.customCV,
              let url = URL(string: "\(cvEndpoint)?profile=\(profile)&jobId=\(jobId)") else { throw CVUploadError.missing }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CVUploadError.missing }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AppliedCVs", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(cv.name.hasSuffix(".pdf") ? cv.name : "\(cv.name).pdf")
        try data.write(to: file, options: .atomic)
        return file
    }

    func removeCV(_ jobId: Int) async throws {
        guard let url = URL(string: "\(cvEndpoint)?profile=\(profile)&jobId=\(jobId)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        let (_, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CVUploadError.rejected }
        guard let i = applications.firstIndex(where: { $0.id == jobId }) else { return }
        applications[i].customCV = nil
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
