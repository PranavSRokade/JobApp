import Foundation

struct CVProfileBullet: Codable, Identifiable {
    var id: String
    var pinned: Bool
    var skills: [String]
    var latex: String

    init(id: String, pinned: Bool, skills: [String], latex: String) {
        self.id = id; self.pinned = pinned; self.skills = skills; self.latex = latex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        skills = try c.decode([String].self, forKey: .skills)
        latex = try c.decode(String.self, forKey: .latex)
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

struct CVProfileBulletPools: Codable {
    var nHabit: [CVProfileBullet]
    var campConnection: [CVProfileBullet]
    var projexino: [CVProfileBullet]
    var samyak: [CVProfileBullet]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nHabit = try c.decode([CVProfileBullet].self, forKey: .nHabit)
        campConnection = try c.decode([CVProfileBullet].self, forKey: .campConnection)
        projexino = try c.decode([CVProfileBullet].self, forKey: .projexino)
        samyak = try c.decodeIfPresent([CVProfileBullet].self, forKey: .samyak) ?? []
    }

    func pool(for company: CVCompany) -> [CVProfileBullet] {
        switch company {
        case .nHabit: return nHabit
        case .campConnection: return campConnection
        case .projexino: return projexino
        case .samyak: return samyak
        }
    }

    mutating func setPool(_ bullets: [CVProfileBullet], for company: CVCompany) {
        switch company {
        case .nHabit: nHabit = bullets
        case .campConnection: campConnection = bullets
        case .projexino: projexino = bullets
        case .samyak: samyak = bullets
        }
    }
}

// Per-profile text knobs used by the worker when building the CV (blank = worker default)
struct CVSettings: Codable, Equatable {
    var yearsExperience: String   // "3.5+" → "with 3.5+ years of experience"
    var summaryDegree: String     // short degree name in the summary paragraph
    var educationTitle: String    // full LaTeX heading under Education

    static let empty = CVSettings(yearsExperience: "", summaryDegree: "", educationTitle: "")
}

struct CVProfile: Codable {
    var skills: [String]
    var bullets: CVProfileBulletPools
    var hasCustomTemplate: Bool
    var hasCustomPrompt: Bool?
    var settings: CVSettings?
}
