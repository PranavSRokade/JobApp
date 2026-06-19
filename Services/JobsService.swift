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

    static func fetchJobs(profile: String, sheet: String? = nil) async throws -> JobsResponse {
        guard var components = URLComponents(string: baseURL) else {
            throw JobsServiceError.invalidURL
        }
        var queryItems = [URLQueryItem(name: "profile", value: profile)]
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
