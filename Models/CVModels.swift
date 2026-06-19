import Foundation

struct CVDecisions: Codable {
    var role: String
    var skills: [String]
    var focusArea: String?
    var nHabitBullets: [Int]
    var campBullets: [Int]
    var projexinoBullets: [Int]
    var projectKey: String
    var skillsLine: String
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
    let skillsArray: [String]
    let projectOptions: [CVProjectOption]

    func pool(for company: CVCompany) -> [CVBulletEntry] {
        switch company {
        case .nHabit: return nHabit
        case .campConnection: return campConnection
        case .projexino: return projexino
        }
    }
}

enum CVCompany: String, CaseIterable {
    case nHabit, campConnection, projexino

    var displayName: String {
        switch self {
        case .nHabit: return "nHabit"
        case .campConnection: return "Camp Connection"
        case .projexino: return "Projexino"
        }
    }

    func selectedIndices(in decisions: CVDecisions) -> [Int] {
        switch self {
        case .nHabit: return decisions.nHabitBullets
        case .campConnection: return decisions.campBullets
        case .projexino: return decisions.projexinoBullets
        }
    }
}

struct CVResult: Codable {
    var latex: String
    var pdfData: Data
    var decisions: CVDecisions
    var pools: CVBulletPools
}
