import Combine
import Foundation

/// A job added by hand from the Jobs page, listed under "Added by you" on its market's page until
/// it is marked applied (it then lives in Applications) or deleted.
struct AddedJob: Codable, Identifiable {
    let job: Job
    /// "uk", "us" or "ww": the page it is listed on and the market its CV is written for
    let region: String
    let addedAt: Date
    var id: Int { job.jobId }
}

final class AddedJobsStore: ObservableObject {
    /// Ids from here up are jobs added by hand, never scraped ones (LinkedIn ids are about 4e9)
    static let firstId = 900_000_000_000

    @Published private(set) var jobs: [AddedJob] = []
    private let key: String

    init(profile: String) {
        key = "addedJobs.\(profile)"
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([AddedJob].self, from: data) {
            jobs = saved
        }
    }

    /// `taken` says whether an id is already used elsewhere (an application added the old way)
    func add(title: String, company: String, link: String, location: String, jd: String, region: String,
             taken: (Int) -> Bool) -> AddedJob {
        var id = Self.firstId + Int(Date().timeIntervalSince1970)
        while taken(id) || jobs.contains(where: { $0.id == id }) { id += 1 }
        let job = Job(
            rank: 0, title: title, company: company, jobId: id, link: link, over100: false, age: "",
            location: location, skills: 0, experience: 0, seniority: 0, locationFit: 0, companySize: 0,
            scoreSource: "", jd: jd, sponsorship: nil, salary: nil, visaNotes: nil, applicants: nil
        )
        let added = AddedJob(job: job, region: region, addedAt: Date())
        jobs.insert(added, at: 0)
        persist()
        return added
    }

    func remove(_ id: Int) {
        jobs.removeAll { $0.id == id }
        persist()
    }

    func jobs(in region: String) -> [AddedJob] { jobs.filter { $0.region == region } }

    private func persist() {
        if let data = try? JSONEncoder().encode(jobs) { UserDefaults.standard.set(data, forKey: key) }
    }
}
