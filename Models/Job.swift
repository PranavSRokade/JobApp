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
    // "yes" | "no" | "na" from the scorer; nil/"" on tabs scraped before Oct 2026
    let sponsorship: String?
    // "£55,000 – £65,000" when the posting states pay; nil/"" otherwise
    let salary: String?
    // the visa/work-authorisation sentences the scorer based `sponsorship` on
    let visaNotes: String?
    // LinkedIn's applicant caption when scraped, e.g. "31 applicants", "Over 200 applicants"
    let applicants: String?

    var id: Int { jobId }

    var applicantsText: String? { (applicants ?? "").isEmpty ? nil : applicants }

    var sponsored: Bool { sponsorship == "yes" }
    var noSponsorship: Bool { sponsorship == "no" }
    var salaryText: String? { (salary ?? "").isEmpty ? nil : salary }
    var visaNotesText: String? { (visaNotes ?? "").isEmpty ? nil : visaNotes }

    var averageScore: Int {
        (skills + experience + seniority + locationFit + companySize) / 5
    }
}

struct JobsResponse: Codable {
    let sheet: String?
    let sheets: [String]
    let profile: String
    let region: String?
    let jobs: [Job]
}
