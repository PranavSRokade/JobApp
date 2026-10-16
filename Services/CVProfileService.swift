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

    // MARK: Settings (years of experience, degree text, education heading)

    static func saveSettings(_ settings: CVSettings, for profile: String) async throws {
        _ = try await put(path: "/api/profile/settings?profile=\(profile)", body: settings)
    }

    // MARK: CV prompt template

    struct PromptInfo: Decodable {
        let prompt: String
        let isCustom: Bool
        let defaultPrompt: String
        let placeholders: [String]
    }

    static func fetchPrompt(for profile: String) async throws -> PromptInfo {
        guard let url = URL(string: "\(base)/api/profile/prompt?profile=\(profile)") else { throw CVServiceError.decodingError }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(PromptInfo.self, from: data)
    }

    static func savePrompt(_ text: String, for profile: String) async throws {
        guard let url = URL(string: "\(base)/api/profile/prompt?profile=\(profile)") else { throw CVServiceError.decodingError }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        req.httpBody = text.data(using: .utf8)
        req.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Save failed"
            throw CVServiceError.server(status, msg)
        }
    }

    static func resetPrompt(for profile: String) async throws {
        guard let url = URL(string: "\(base)/api/profile/prompt?profile=\(profile)") else { throw CVServiceError.decodingError }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.timeoutInterval = 30
        let (_, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CVServiceError.decodingError }
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

    struct SuggestedBullet: Decodable, Identifiable {
        var id = UUID()
        let latex: String
        let skills: [String]
        private enum CodingKeys: String, CodingKey { case latex, skills }
    }

    static func chatBullets(
        messages: [(role: String, content: String)],
        company: String,
        profile: String
    ) async throws -> (text: String, bullets: [SuggestedBullet]) {
        struct Msg: Encodable { let role: String; let content: String }
        struct Body: Encodable { let messages: [Msg]; let company: String; let profile: String }
        struct Resp: Decodable { let text: String; let bullets: [SuggestedBullet] }
        let body = Body(messages: messages.map { Msg(role: $0.role, content: $0.content) }, company: company, profile: profile)
        guard let url = URL(string: "\(base)/api/cv/chat-bullets") else { throw CVServiceError.decodingError }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        req.timeoutInterval = 30
        let (data, _) = try await URLSession.shared.data(for: req)
        let resp = try JSONDecoder().decode(Resp.self, from: data)
        return (resp.text, resp.bullets)
    }

    static func suggestBullets(description: String, company: String, profile: String) async throws -> [SuggestedBullet] {
        struct Body: Encodable { let description: String; let company: String; let profile: String }
        struct Resp: Decodable { let bullets: [SuggestedBullet] }
        guard let url = URL(string: "\(base)/api/cv/suggest-bullets") else { throw CVServiceError.decodingError }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(Body(description: description, company: company, profile: profile))
        req.timeoutInterval = 30
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try JSONDecoder().decode(Resp.self, from: data)).bullets
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
