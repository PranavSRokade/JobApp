import Foundation

struct CVDecisions: Codable {
    var role: String
    var skills: [String]
    var focusArea: String?
    var nHabitBullets: [Int]
    var campBullets: [Int]
    var projexinoBullets: [Int]
    var samyakBullets: [Int]
    var projectKey: String
    var skillsLine: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role = try c.decode(String.self, forKey: .role)
        skills = try c.decode([String].self, forKey: .skills)
        focusArea = try c.decodeIfPresent(String.self, forKey: .focusArea)
        nHabitBullets = try c.decode([Int].self, forKey: .nHabitBullets)
        campBullets = try c.decode([Int].self, forKey: .campBullets)
        projexinoBullets = try c.decode([Int].self, forKey: .projexinoBullets)
        samyakBullets = try c.decodeIfPresent([Int].self, forKey: .samyakBullets) ?? []
        projectKey = try c.decode(String.self, forKey: .projectKey)
        skillsLine = try c.decode(String.self, forKey: .skillsLine)
    }
}

struct CVBulletEntry: Codable, Identifiable {
    let index: Int
    let displayText: String
    let pinned: Bool
    let skills: [String]
    var id: Int { index }
}

struct CVProjectOption: Codable, Identifiable {
    let key: String
    let title: String
    var id: String { key }
}

struct CVBulletPools: Codable {
    let nHabit: [CVBulletEntry]
    let campConnection: [CVBulletEntry]
    let projexino: [CVBulletEntry]
    let samyak: [CVBulletEntry]
    let skillsArray: [String]
    let projectOptions: [CVProjectOption]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nHabit = try c.decode([CVBulletEntry].self, forKey: .nHabit)
        campConnection = try c.decode([CVBulletEntry].self, forKey: .campConnection)
        projexino = try c.decode([CVBulletEntry].self, forKey: .projexino)
        samyak = try c.decodeIfPresent([CVBulletEntry].self, forKey: .samyak) ?? []
        skillsArray = try c.decode([String].self, forKey: .skillsArray)
        projectOptions = try c.decode([CVProjectOption].self, forKey: .projectOptions)
    }

    init(nHabit: [CVBulletEntry], campConnection: [CVBulletEntry], projexino: [CVBulletEntry],
         samyak: [CVBulletEntry] = [], skillsArray: [String], projectOptions: [CVProjectOption]) {
        self.nHabit = nHabit; self.campConnection = campConnection
        self.projexino = projexino; self.samyak = samyak
        self.skillsArray = skillsArray; self.projectOptions = projectOptions
    }

    func pool(for company: CVCompany) -> [CVBulletEntry] {
        switch company {
        case .nHabit: return nHabit
        case .campConnection: return campConnection
        case .projexino: return projexino
        case .samyak: return samyak
        }
    }
}

enum CVCompany: String, CaseIterable {
    case nHabit, campConnection, projexino, samyak

    static func cases(for profile: String) -> [CVCompany] {
        profile == "gf" ? [.nHabit, .campConnection, .projexino, .samyak] : [.nHabit, .campConnection, .projexino]
    }

    var displayName: String { displayName(for: "spencer") }

    func displayName(for profile: String) -> String {
        if profile == "gf" {
            switch self {
            case .nHabit: return "HRUC"
            case .campConnection: return "Kith & Kids"
            case .projexino: return "White Lodge"
            case .samyak: return "Samyak"
            }
        }
        switch self {
        case .nHabit: return "nHabit"
        case .campConnection: return "Camp Connection"
        case .projexino: return "Projexino"
        case .samyak: return "Samyak"
        }
    }

    func selectedIndices(in decisions: CVDecisions) -> [Int] {
        switch self {
        case .nHabit: return decisions.nHabitBullets
        case .campConnection: return decisions.campBullets
        case .projexino: return decisions.projexinoBullets
        case .samyak: return decisions.samyakBullets
        }
    }
}

struct CVResult: Codable {
    var latex: String
    var pdfData: Data
    var decisions: CVDecisions
    var pools: CVBulletPools
}
