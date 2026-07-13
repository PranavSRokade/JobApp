import Foundation

struct CVProfileService {
    private static let base = "https://job-worker.pranavrokade.workers.dev"

    static func fetchProfile(for profile: String) async throws -> CVProfile {
        guard let url = URL(string: "\(base)/api/profile?profile=\(profile)") else { throw CVServiceError.decodingError }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let result = try? JSONDecoder().decode(CVProfile.self, from: data) else {
            throw CVServiceError.decodingError
        }
        return result
    }

    static func saveSkills(_ skills: [String], for profile: String) async throws {
        struct Body: Encodable { let skills: [String] }
        _ = try await put(path: "/api/profile/skills?profile=\(profile)", body: Body(skills: skills))
    }

    static func saveBullets(_ pools: CVProfileBulletPools, for profile: String) async throws {
        struct Body: Encodable { let bullets: CVProfileBulletPools }
        _ = try await put(path: "/api/profile/bullets?profile=\(profile)", body: Body(bullets: pools))
    }

    static func uploadTemplate(_ tex: String, for profile: String) async throws {
        guard let url = URL(string: "\(base)/api/profile/template?profile=\(profile)") else { throw CVServiceError.decodingError }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        req.httpBody = tex.data(using: .utf8)
        req.timeoutInterval = 30
        let (_, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CVServiceError.decodingError }
    }

    struct TitleFilters: Codable {
        var allowed: [String]
        var blocked: [String]
        var blockedCompanies: [String]
    }

    static func fetchTitleFilters(for profile: String) async throws -> TitleFilters {
        guard let url = URL(string: "\(base)/api/profile/filters?profile=\(profile)") else { throw CVServiceError.decodingError }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let result = try? JSONDecoder().decode(TitleFilters.self, from: data) else { throw CVServiceError.decodingError }
        return result
    }

    static func saveTitleFilters(_ filters: TitleFilters, for profile: String) async throws {
        _ = try await put(path: "/api/profile/filters?profile=\(profile)", body: filters)
    }

    static func fetchDefaultTemplate(for profile: String) async throws -> String {
        guard let url = URL(string: "\(base)/api/profile/default-template?profile=\(profile)") else { throw CVServiceError.decodingError }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let text = String(data: data, encoding: .utf8) else { throw CVServiceError.decodingError }
        return text
    }

    static func deleteTemplate(for profile: String) async throws {
        guard let url = URL(string: "\(base)/api/profile/template?profile=\(profile)") else { throw CVServiceError.decodingError }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.timeoutInterval = 30
        let (_, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CVServiceError.decodingError }
    }

    private static func put<B: Encodable>(path: String, body: B) async throws -> Data {
        guard let url = URL(string: "\(base)\(path)") else { throw CVServiceError.decodingError }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        req.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CVServiceError.decodingError }
        return data
    }
}
