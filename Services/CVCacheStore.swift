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

    static func delete(for jobId: Int) {
        let url = cacheDir.appendingPathComponent("\(jobId).json")
        try? FileManager.default.removeItem(at: url)
    }

    static func deleteAll(for jobIds: [Int]) {
        jobIds.forEach { delete(for: $0) }
    }
}
