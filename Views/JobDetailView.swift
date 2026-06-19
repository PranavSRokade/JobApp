import SwiftUI

struct JobDetailView: View {
    let job: Job
    let sheetName: String?
    @ObservedObject var starredStore: StarredJobsStore
    var profile: String = "spencer"

    @State private var isGeneratingCV = false
    @State private var cvResult: CVResult? = nil
    @State private var cvError: String? = nil

    private var isStarred: Bool { starredStore.isStarred(job.jobId) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text(job.title)
                        .font(.title2.bold())
                    Text(job.company)
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Label(job.location, systemImage: "location")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Label(actualAge(sheetName: sheetName, ageText: job.age), systemImage: "clock")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if job.over100 {
                        Label("100+ applicants", systemImage: "person.3")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    }
                }

                Divider()

                // Scores grid
                Text("Scores")
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ScoreCard(label: "Skills", value: job.skills)
                    ScoreCard(label: "Experience", value: job.experience)
                    ScoreCard(label: "Seniority", value: job.seniority)
                    ScoreCard(label: "Location Fit", value: job.locationFit)
                    ScoreCard(label: "Company Size", value: job.companySize)
                    ScoreCard(label: "Overall", value: job.averageScore)
                }

                if job.scoreSource == "full-jd" {
                    Label("Scored from full JD", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                }

                Divider()

                // Open / share LinkedIn
                if let url = URL(string: job.link) {
                    HStack(spacing: 8) {
                        Link(destination: url) {
                            Label("View on LinkedIn", systemImage: "arrow.up.right.square")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                                .padding()
                                .background(Color.blue.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                // Generate CV (Pranav only, requires a JD)
                if profile == "spencer", let jd = job.jd {
                    Button {
                        isGeneratingCV = true
                        cvError = nil
                        Task {
                            do {
                                cvResult = try await CVService.generateCV(jd: jd)
                            } catch {
                                cvError = error.localizedDescription
                            }
                            isGeneratingCV = false
                        }
                    } label: {
                        Group {
                            if isGeneratingCV {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    Text("Generating CV…")
                                }
                            } else {
                                Label("Generate CV", systemImage: "doc.text.fill")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isGeneratingCV)

                    if let err = cvError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                }

                // JD
                let jdText = job.jd ?? JobDetailView.testJD
                Divider()
                JDSectionView(text: jdText)
            }
            .padding()
        }
        .navigationTitle(job.company)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    starredStore.toggle(job.jobId)
                } label: {
                    Image(systemName: isStarred ? "star.fill" : "star")
                        .foregroundColor(isStarred ? .yellow : .secondary)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { cvResult != nil },
            set: { if !$0 { cvResult = nil } }
        )) {
            if let result = cvResult {
                CVPreviewView(jd: job.jd ?? "", result: result)
            }
        }
    }
}

// MARK: - JD Display

private enum JDLine {
    case heading(String)   // bold section title
    case bullet(String)    // • item
    case body(String)      // regular paragraph line
}

private func parseJDLines(_ text: String) -> [JDLine] {
    text.components(separatedBy: "\n").compactMap { raw in
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }

        // *heading* format from job-tracker
        if t.hasPrefix("*") && t.hasSuffix("*") && t.count > 2 {
            let inner = String(t.dropFirst().dropLast())
            if !inner.contains("*") { return .heading(inner) }
        }
        // Short standalone line → heading (≤60 chars, no trailing sentence punctuation, no bullet)
        if t.count <= 60 && !t.hasPrefix("•") && !t.hasSuffix(".") && !t.hasSuffix(",") && !t.hasSuffix(";") {
            return .heading(t)
        }
        if t.hasPrefix("•") { return .bullet(String(t.dropFirst().trimmingCharacters(in: .whitespaces))) }
        return .body(t)
    }
}

/// Converts *bold* markers to bold in an AttributedString.
private func styledText(_ raw: String) -> AttributedString {
    var result = AttributedString()
    var remaining = raw[...]
    while let start = remaining.range(of: "*") {
        let before = remaining[remaining.startIndex..<start.lowerBound]
        if !before.isEmpty { result += AttributedString(String(before)) }
        let afterStar = remaining[start.upperBound...]
        if let end = afterStar.range(of: "*") {
            var bold = AttributedString(String(afterStar[afterStar.startIndex..<end.lowerBound]))
            bold.font = .system(size: 14, weight: .semibold)
            result += bold
            remaining = afterStar[end.upperBound...]
        } else {
            result += AttributedString("*")
            remaining = afterStar
        }
    }
    if !remaining.isEmpty { result += AttributedString(String(remaining)) }
    return result
}

private struct JDSectionView: View {
    let text: String
    @State private var expanded = false

    private var lines: [JDLine] { parseJDLines(text) }

    private var headingCount: Int {
        var count = 0
        for line in lines {
            if case .heading = line { count += 1 }
            if count == 3 { break }
        }
        return count
    }

    private func visibleLines() -> [JDLine] {
        guard !expanded else { return lines }
        // Show up to the third heading (exclusive) so we preview ~2 sections
        var headings = 0
        var result: [JDLine] = []
        for line in lines {
            if case .heading = line {
                headings += 1
                if headings == 3 { break }
            }
            result.append(line)
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Job Description")
                    .font(.headline)
                Spacer()
                Button(expanded ? "Show less" : "Show more") {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(visibleLines().enumerated()), id: \.offset) { _, line in
                    switch line {
                    case .heading(let t):
                        Text(t)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.primary)
                            .padding(.top, 6)

                    case .bullet(let t):
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            Text(styledText(t))
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                    case .body(let t):
                        Text(styledText(t))
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// MARK: - Test data (remove once job-tracker populates FULL_JD column)

private extension JobDetailView {
    static let testJD = """
This is a job that Jill, our AI Recruiter, is recruiting for on behalf of one of our customers.

She will pick the best candidates from Jack's network.

The next step is to speak to Jack.

Job Title

Intermediate Software Engineer (React)

Salary

£75k

Company Description

Goodlord is a £17M-backed, profitable PropTech scale-up in London revolutionizing the rental market for over 1 million tenants annually.

Job Description

Join a top-tier engineering team building a digital-first rental platform. You will develop complex features using React and TypeScript, transitioning legacy interfaces into a modern frontend architecture. Working in self-organizing squads, you'll solve real-world problems for thousands of agents while benefiting from a culture that prioritizes learning and professional growth.

Location

London, UK

Why this role is remarkable

Work on a platform processing over £1B in annual transactions, directly impacting the lives of millions of renters and thousands of letting agents across the UK.
Join a "Great Place to Work" certified organization with an 83% employee endorsement rate, ranked among the UK's top tech employers for wellbeing and development.
Access a £1,000 annual development fund and 3 months of fully-paid parental leave, within a profitable scale-up that values transparency and stable career progression.

What You Will Do

Deliver high-impact features using React and TypeScript, contributing to the strategic migration of the platform's UI toward a fully modern React architecture.
Pair with senior engineers to architect and spec complex features, ensuring code quality through peer reviews and comprehensive automated unit testing.
Participate in self-organizing agile squads using Kanban, collaborating closely with stakeholders to iterate quickly based on direct user feedback and market regulatory changes.

The ideal candidate

Possesses 5-8 years of commercial experience with React and TypeScript in a production environment, ideally within a product-led company.
Demonstrates strong computer science foundations, proficiency with relational databases (MySQL/Aurora), and a deep understanding of web application security and common vulnerabilities.
Exhibits a collaborative mindset, comfortable with ambiguity and eager to learn new technologies like PHP/Symfony or utility-first CSS frameworks like Tailwind.

Who are Jack & Jill?

Ok, I'll go first. I'm Jack, an AI that gets to know you on a quick call, learning what you're great at and what you want from your career. Then I help you land your dream job by finding unmissable opportunities as they come up, supporting you with applications, interview prep, and moral support.

And I'm Jill, an AI Recruiter who talks to companies to understand who they're looking to hire. Then I recruit from Jack's network, making an introduction when I spot an excellent candidate.

How does this work?

Jack's an AI agent for job searching and career coaching. He works for you.
Jill is the AI recruiter working for the company. She recruits from Jack's network.
If it's a match and the company wants to meet you, they'll make the intro. In the meantime, if you'd like, Jack will send you excellent alternatives.
"""
}

private struct ScoreCard: View {
    let label: String
    let value: Int

    private var color: Color {
        switch value {
        case 80...: return .green
        case 60..<80: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
