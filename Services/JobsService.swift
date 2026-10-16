import Foundation

enum JobsServiceError: LocalizedError {
    case invalidURL
    case noData
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .noData: return "No data received"
        case .server(let msg): return msg
        }
    }
}

struct JobsService {
    private static let baseURL = "https://job-worker.pranavrokade.workers.dev/api/jobs"

    static func fetchJobs(profile: String, sheet: String? = nil, region: String = "uk") async throws -> JobsResponse {
        guard var components = URLComponents(string: baseURL) else {
            throw JobsServiceError.invalidURL
        }
        var queryItems = [
            URLQueryItem(name: "profile", value: profile),
            URLQueryItem(name: "region", value: region),
        ]
        if let sheet { queryItems.append(URLQueryItem(name: "sheet", value: sheet)) }
        components.queryItems = queryItems
        guard let url = components.url else { throw JobsServiceError.invalidURL }

        let (data, response) = try await URLSession.shared.data(from: url)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw JobsServiceError.server(body)
        }

        return try JSONDecoder().decode(JobsResponse.self, from: data)
    }

    /// Fetches a job's description on demand (for rows the scraper couldn't fetch) and asks the
    /// worker to store it in the sheet so it's there next time, on every device.
    static func fetchJobDescription(url: String, profile: String, sheet: String?, jobId: Int) async throws -> String {
        struct Body: Encodable { let url: String; let profile: String; let sheet: String?; let jobId: Int }
        struct Resp: Decodable { let jd: String?; let savedToSheet: Bool?; let error: String? }
        guard let endpoint = URL(string: "https://job-worker.pranavrokade.workers.dev/api/jd") else { throw JobsServiceError.invalidURL }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(url: url, profile: profile, sheet: sheet, jobId: jobId))
        request.timeoutInterval = 45
        let (data, response) = try await URLSession.shared.data(for: request)
        let decoded = try? JSONDecoder().decode(Resp.self, from: data)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw JobsServiceError.server(decoded?.error ?? "Could not fetch the description")
        }
        guard let jd = decoded?.jd, !jd.isEmpty else { throw JobsServiceError.noData }
        JDCache.save(jd, for: jobId)
        return jd
    }
}

/// Descriptions fetched on demand, kept on-device so the job opens instantly next time
/// even if the sheet write-back failed.
enum JDCache {
    private static func key(_ jobId: Int) -> String { "jd_\(jobId)" }
    static func load(for jobId: Int) -> String? { UserDefaults.standard.string(forKey: key(jobId)) }
    static func save(_ jd: String, for jobId: Int) { UserDefaults.standard.set(jd, forKey: key(jobId)) }
}

extension JobsService {
    static func deleteSheets(profile: String, sheets: Set<String>) async throws {
        guard var components = URLComponents(string: "https://job-worker.pranavrokade.workers.dev/api/sheet") else {
            throw JobsServiceError.invalidURL
        }
        var queryItems = [URLQueryItem(name: "profile", value: profile)]
        for sheet in sheets {
            queryItems.append(URLQueryItem(name: "sheet", value: sheet))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw JobsServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw JobsServiceError.server(body)
        }
    }
}
