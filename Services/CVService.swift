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

struct CVResult {
    let latex: String
    let pdfData: Data
}

private struct CVResponse: Decodable {
    let latex: String
    let pdf: String // base64-encoded PDF
}

struct CVService {
    private static let baseURL = "https://job-worker.pranavrokade.workers.dev"

    static func generateCV(jd: String) async throws -> CVResult {
        guard let url = URL(string: "\(baseURL)/api/cv") else {
            throw CVServiceError.decodingError
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90
        request.httpBody = try JSONEncoder().encode(["jd": jd])

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CVServiceError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw CVServiceError.decodingError
        }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw CVServiceError.server(http.statusCode, msg)
        }

        guard
            let decoded = try? JSONDecoder().decode(CVResponse.self, from: data),
            let pdfData = Data(base64Encoded: decoded.pdf)
        else {
            throw CVServiceError.decodingError
        }

        return CVResult(latex: decoded.latex, pdfData: pdfData)
    }
}
