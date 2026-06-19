import Foundation

struct Job: Codable, Identifiable {
    let rank: Int
    let title: String
    let company: String
    let jobId: Int
    let link: String
    let over100: Bool
    let age: String
    let location: String
    let skills: Int
    let experience: Int
    let seniority: Int
    let locationFit: Int
    let companySize: Int
    let scoreSource: String
    let jd: String?

    var id: Int { jobId }

    var averageScore: Int {
        (skills + experience + seniority + locationFit + companySize) / 5
    }
}

struct JobsResponse: Codable {
    let sheet: String?
    let sheets: [String]
    let profile: String
    let jobs: [Job]
}
