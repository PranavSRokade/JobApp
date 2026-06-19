import SwiftUI

struct JobRowView: View {
    let job: Job
    let sheetName: String?
    @ObservedObject var starredStore: StarredJobsStore

    private var isStarred: Bool { starredStore.isStarred(job.jobId) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Rank badge with optional star overlay
            ZStack(alignment: .topTrailing) {
                Text("\(job.rank)")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(rankColor)
                    .clipShape(Circle())

                if isStarred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.yellow)
                        .background(Circle().fill(Color.white).frame(width: 13, height: 13))
                        .offset(x: 4, y: -4)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(job.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Text(job.company)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    if job.over100 {
                        Text("100+")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .clipShape(Capsule())
                    }
                }

                Text(job.location)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                HStack(spacing: 2) {
                    Text(actualAge(sheetName: sheetName, ageText: job.age))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    if job.scoreSource == "full-jd" {
                        Text("· JD scored")
                            .font(.system(size: 11))
                            .foregroundColor(.blue.opacity(0.7))
                    }
                }
            }

            Spacer()

            VStack(spacing: 6) {
                ScoreBadgeView(label: "SKL", value: job.skills)
                ScoreBadgeView(label: "EXP", value: job.experience)
                ScoreBadgeView(label: "FIT", value: job.locationFit)
            }
        }
        .padding(.vertical, 6)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                starredStore.toggle(job.jobId)
            } label: {
                Label(isStarred ? "Unstar" : "Star", systemImage: isStarred ? "star.slash.fill" : "star.fill")
            }
            .tint(.yellow)
        }
    }

    private var rankColor: Color {
        switch job.rank {
        case 90...: return .green
        case 75..<90: return .blue
        case 60..<75: return .orange
        default: return .gray
        }
    }
}
