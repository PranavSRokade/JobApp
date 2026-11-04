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

/// One job's dates on the CV, matched to the template's heading by company name
struct JobDate: Codable, Equatable {
    var company: String
    var dates: String
}

// Per-profile text knobs used by the worker when building the CV (blank = worker default)
struct CVSettings: Codable, Equatable {
    var yearsExperience: String   // "3.5+" → "with 3.5+ years of experience"
    var summaryDegree: String     // short degree name in the summary paragraph
    var educationTitle: String    // full LaTeX heading under Education
    var summaryEducationLine: String = ""  // the summary's whole education sentence; **bold**; blank = built from the degree
    var jobDates: [JobDate] = []           // only the jobs whose dates differ from the template

    static let empty = CVSettings(yearsExperience: "", summaryDegree: "", educationTitle: "")

    /// Replacements for "Recently completed an MSc …", which read oddly a year on (Nov 2026)
    static func educationLineSuggestions(degree: String) -> [String] {
        let d = degree.trimmingCharacters(in: .whitespaces).isEmpty ? "MSc in Advanced Software Engineering" : degree
        return [
            "Holds an **\(d)** from **King's College London**.",
            "Backed by an **\(d)** from **King's College London**.",
            "Combines an **\(d)** from **King's College London** with hands-on production delivery.",
            "Postgraduate-qualified with an **\(d)** from **King's College London**, applied daily in production work.",
            "**\(d)** graduate of **King's College London**, now shipping production apps end to end.",
        ]
    }
}

extension CVSettings {
    // Cached and older payloads predate the last two fields
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        yearsExperience = try c.decodeIfPresent(String.self, forKey: .yearsExperience) ?? ""
        summaryDegree = try c.decodeIfPresent(String.self, forKey: .summaryDegree) ?? ""
        educationTitle = try c.decodeIfPresent(String.self, forKey: .educationTitle) ?? ""
        summaryEducationLine = try c.decodeIfPresent(String.self, forKey: .summaryEducationLine) ?? ""
        jobDates = try c.decodeIfPresent([JobDate].self, forKey: .jobDates) ?? []
    }
}

struct CVProfile: Codable {
    var skills: [String]
    var bullets: CVProfileBulletPools
    var hasCustomTemplate: Bool
    var hasCustomPrompt: Bool?
    var settings: CVSettings?
}
