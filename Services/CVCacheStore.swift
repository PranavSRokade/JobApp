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

    static func delete(for jobId: Int) {
        let url = cacheDir.appendingPathComponent("\(jobId).json")
        try? FileManager.default.removeItem(at: url)
    }

    static func deleteAll(for jobIds: [Int]) {
        jobIds.forEach { delete(for: $0) }
    }
}
