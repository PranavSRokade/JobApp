import Foundation
import Combine
import SwiftUI

enum MessageRole: String, Codable { case user, assistant }

struct PersistedBullet: Codable, Identifiable {
    var id: UUID
    var latex: String
    var skills: [String]

    init(latex: String, skills: [String]) {
        id = UUID(); self.latex = latex; self.skills = skills
    }

    var displayText: String {
        latex
            .replacingOccurrences(of: #"\\textbf\{([^}]*)\}"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\\textit\{([^}]*)\}"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\&", with: "&")
            .replacingOccurrences(of: "\\%", with: "%")
            .trimmingCharacters(in: .whitespaces)
    }
}

struct ChatMessage: Codable, Identifiable {
    var id: UUID
    var role: MessageRole
    var content: String
    var bullets: [PersistedBullet]
    var timestamp: Date

    init(role: MessageRole, content: String, bullets: [PersistedBullet] = []) {
        id = UUID(); self.role = role; self.content = content
        self.bullets = bullets; self.timestamp = Date()
    }
}

struct FeatureChat: Codable, Identifiable {
    var id: UUID
    var title: String
    var company: CVCompany
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date

    init(company: CVCompany) {
        id = UUID(); title = "New Feature"; self.company = company
        messages = []; createdAt = Date(); updatedAt = Date()
    }
}

final class FeatureChatStore: ObservableObject {
    @Published var chats: [FeatureChat] = []
    private let key: String

    init(profile: String) {
        key = "featureChats_\(profile)"
        load()
    }

    func create(company: CVCompany) -> FeatureChat {
        let chat = FeatureChat(company: company)
        chats.insert(chat, at: 0)
        persist()
        return chat
    }

    func update(_ chat: FeatureChat) {
        guard let idx = chats.firstIndex(where: { $0.id == chat.id }) else { return }
        chats[idx] = chat
        persist()
    }

    func delete(at offsets: IndexSet) {
        chats.remove(atOffsets: offsets)
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([FeatureChat].self, from: data) else { return }
        chats = saved
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(chats) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
