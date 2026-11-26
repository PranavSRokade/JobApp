import Foundation

struct CVCacheStore {
    private static var cacheDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CVCache", isDirectory: true)
    }

    static func save(_ result: CVResult, for jobId: Int) {
        let dir = cacheDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(jobId).json")
        try? JSONEncoder().encode(result).write(to: url, options: .atomic)
    }

    static func load(for jobId: Int) -> CVResult? {
        let url = cacheDir.appendingPathComponent("\(jobId).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CVResult.self, from: data)
    }

    /// Cheap check for "is there a saved CV" without decoding the PDF, for use in view bodies.
    static func exists(for jobId: Int) -> Bool {
        FileManager.default.fileExists(atPath: cacheDir.appendingPathComponent("\(jobId).json").path)
    }

    static func delete(for jobId: Int) {
        let url = cacheDir.appendingPathComponent("\(jobId).json")
        try? FileManager.default.removeItem(at: url)
    }

    static func deleteAll(for jobIds: [Int]) {
        jobIds.forEach { delete(for: $0) }
    }

    /// When the job's CV was last generated or rebuilt
    static func savedAt(for jobId: Int) -> Date? {
        let path = cacheDir.appendingPathComponent("\(jobId).json").path
        return (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}

/// Copies a job's CV (with its LaTeX) and cover letter to the worker, so JobFill, the Safari
/// extension, uses those exact files on the company's application page and grounds its drafted
/// answers in that CV. Each part uploads only when it is newer than its last upload.
enum PreparedCVSync {
    private static func uploadedKey(_ part: String, _ profile: String, _ jobId: Int) -> String { "prepared\(part).\(profile).\(jobId)" }

    static func syncIfNeeded(job: Job, region: String, sheet: String?, profile: String) async {
        guard job.jobId > 0 else { return }
        let cvKey = uploadedKey("CVWithText", profile, job.jobId) // "CV" uploads from before the LaTeX was sent go again once
        let letterKey = uploadedKey("Letter", profile, job.jobId)
        func isNew(_ saved: Date?, _ key: String) -> Bool {
            guard let saved else { return false }
            return (UserDefaults.standard.object(forKey: key) as? Date).map { $0 < saved } ?? true
        }
        let cvSaved = CVCacheStore.savedAt(for: job.jobId)
        let letterSaved = CoverLetterCacheStore.savedAt(for: job.jobId)
        let cv = isNew(cvSaved, cvKey) ? CVCacheStore.load(for: job.jobId) : nil
        let letter = isNew(letterSaved, letterKey) ? CoverLetterCacheStore.load(for: job.jobId) : nil
        guard cv != nil || letter != nil,
              let url = URL(string: "https://job-worker.pranavrokade.workers.dev/api/prepared-cv?profile=\(profile)&jobId=\(job.jobId)")
        else { return }

        struct Letter: Encodable { let pdf: String; let text: String; let fileName: String }
        struct Body: Encodable {
            let job: Job; let region: String; let sheet: String?
            let fileName: String?; let pdf: String?; let latex: String?; let letter: Letter?
        }
        let body = Body(
            job: job, region: region, sheet: sheet,
            fileName: cv.map { _ in resumeFileName(title: job.title, company: job.company, location: job.location) },
            pdf: cv?.pdfData.base64EncodedString(), latex: cv?.latex,
            letter: letter.map { Letter(pdf: $0.pdfData.base64EncodedString(), text: $0.text,
                                        fileName: coverLetterFileName(title: job.title, company: job.company, location: job.location)) }
        )
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(body)
        req.timeoutInterval = 60
        guard let (_, response) = try? await WorkerAPI.session.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        if cv != nil { UserDefaults.standard.set(cvSaved, forKey: cvKey) }
        if letter != nil { UserDefaults.standard.set(letterSaved, forKey: letterKey) }
    }
}

/// Same idea for cover letters: the latest generated (or edited and rebuilt) letter per job, so the
/// detail view can offer "use saved" and, once the job is applied to, show what was actually sent.
struct CoverLetterCacheStore {
    private static var cacheDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoverLetterCache", isDirectory: true)
    }

    static func save(_ letter: CoverLetterResult, for jobId: Int) {
        let dir = cacheDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(jobId).json")
        try? JSONEncoder().encode(letter).write(to: url, options: .atomic)
    }

    static func load(for jobId: Int) -> CoverLetterResult? {
        let url = cacheDir.appendingPathComponent("\(jobId).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CoverLetterResult.self, from: data)
    }

    static func exists(for jobId: Int) -> Bool {
        FileManager.default.fileExists(atPath: cacheDir.appendingPathComponent("\(jobId).json").path)
    }

    static func savedAt(for jobId: Int) -> Date? {
        let path = cacheDir.appendingPathComponent("\(jobId).json").path
        return (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    static func delete(for jobId: Int) {
        let url = cacheDir.appendingPathComponent("\(jobId).json")
        try? FileManager.default.removeItem(at: url)
    }

    static func deleteAll(for jobIds: [Int]) {
        jobIds.forEach { delete(for: $0) }
    }
}
