import Foundation

enum CVServiceError: LocalizedError {
    case server(Int, String)
    case networkError(Error)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .server(let code, let msg): return "Server error \(code): \(msg)"
        case .networkError(let e): return e.localizedDescription
        case .decodingError: return "Could not decode CV response"
        }
    }
}

private struct CVGenerateResponse: Decodable {
    let latex: String
    let pdf: String
    let decisions: CVDecisions
    let pools: CVBulletPools
}

private struct CVRebuildResponse: Decodable {
    let latex: String
    let pdf: String
}

struct CVService {
    private static let baseURL = "https://job-worker.pranavrokade.workers.dev"

    static func generateCV(jd: String) async throws -> CVResult {
        let data = try await post(path: "/api/cv", body: ["jd": jd])
        guard
            let decoded = try? JSONDecoder().decode(CVGenerateResponse.self, from: data),
            let pdfData = Data(base64Encoded: decoded.pdf)
        else { throw CVServiceError.decodingError }
        return CVResult(latex: decoded.latex, pdfData: pdfData, decisions: decoded.decisions, pools: decoded.pools)
    }

    static func rebuild(decisions: CVDecisions, jd: String) async throws -> (latex: String, pdfData: Data) {
        struct Body: Encodable { let decisions: CVDecisions; let jd: String }
        let data = try await post(path: "/api/cv-rebuild", body: Body(decisions: decisions, jd: jd))
        guard
            let decoded = try? JSONDecoder().decode(CVRebuildResponse.self, from: data),
            let pdfData = Data(base64Encoded: decoded.pdf)
        else { throw CVServiceError.decodingError }
        return (decoded.latex, pdfData)
    }

    private static func post<B: Encodable>(path: String, body: B) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw CVServiceError.decodingError }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 90
        req.httpBody = try JSONEncoder().encode(body)
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: req) }
        catch { throw CVServiceError.networkError(error) }
        guard let http = response as? HTTPURLResponse else { throw CVServiceError.decodingError }
        guard http.statusCode == 200 else {
            throw CVServiceError.server(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}
