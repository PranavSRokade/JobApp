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

private struct CoverLetterResponse: Decodable {
    let pdf: String
    let text: String
}

struct CVService {
    private static let baseURL = "https://job-worker.pranavrokade.workers.dev"

    static func generateCV(jd: String, profile: String = "spencer") async throws -> CVResult {
        struct Body: Encodable { let jd: String; let profile: String }
        let data = try await post(path: "/api/cv", body: Body(jd: jd, profile: profile))
        guard
            let decoded = try? JSONDecoder().decode(CVGenerateResponse.self, from: data),
            let pdfData = Data(base64Encoded: decoded.pdf)
        else { throw CVServiceError.decodingError }
        return CVResult(latex: decoded.latex, pdfData: pdfData, decisions: decoded.decisions, pools: decoded.pools)
    }

    static func rebuild(decisions: CVDecisions, jd: String, profile: String = "spencer") async throws -> (latex: String, pdfData: Data) {
        struct Body: Encodable { let decisions: CVDecisions; let jd: String; let profile: String }
        let data = try await post(path: "/api/cv-rebuild", body: Body(decisions: decisions, jd: jd, profile: profile))
        guard
            let decoded = try? JSONDecoder().decode(CVRebuildResponse.self, from: data),
            let pdfData = Data(base64Encoded: decoded.pdf)
        else { throw CVServiceError.decodingError }
        return (decoded.latex, pdfData)
    }

    /// First-person answer to an application question ("why do you want to join us…"), grounded in
    /// the JD and the cached CV (or the profile's background when no CV has been generated yet).
    static func generateAnswer(jd: String, company: String, title: String, question: String, latex: String?, profile: String = "spencer") async throws -> String {
        struct Body: Encodable { let jd: String; let company: String; let title: String; let question: String; let latex: String?; let profile: String }
        struct Resp: Decodable { let text: String }
        let data = try await post(path: "/api/answer", body: Body(jd: jd, company: company, title: title, question: question, latex: latex, profile: profile))
        guard let decoded = try? JSONDecoder().decode(Resp.self, from: data), !decoded.text.isEmpty else { throw CVServiceError.decodingError }
        return decoded.text
    }

    static func generateCoverLetter(jd: String, latex: String?, profile: String = "spencer") async throws -> Data {
        struct Body: Encodable { let jd: String; let latex: String?; let profile: String }
        let data = try await post(path: "/api/cover-letter", body: Body(jd: jd, latex: latex, profile: profile))
        guard
            let decoded = try? JSONDecoder().decode(CoverLetterResponse.self, from: data),
            let pdfData = Data(base64Encoded: decoded.pdf)
        else { throw CVServiceError.decodingError }
        return pdfData
    }

    // The worker caps its own AI + LaTeX work at ~85 s worst case, so a hard 110 s total cap here means a
    // request can never spin forever — it either returns or fails with a readable message.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 100
        config.timeoutIntervalForResource = 110
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private static func post<B: Encodable>(path: String, body: B) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw CVServiceError.decodingError }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 100
        req.httpBody = try JSONEncoder().encode(body)
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: req) }
        catch let error as URLError where error.code == .timedOut {
            throw CVServiceError.server(408, "This took too long — the AI providers are busy. Try again in a minute.")
        }
        catch { throw CVServiceError.networkError(error) }
        guard let http = response as? HTTPURLResponse else { throw CVServiceError.decodingError }
        guard http.statusCode == 200 else {
            // Show the worker's message ("AI providers are busy…") rather than raw JSON
            let raw = String(data: data, encoding: .utf8) ?? ""
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? raw
            throw CVServiceError.server(http.statusCode, message)
        }
        return data
    }
}
