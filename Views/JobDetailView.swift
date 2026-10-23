import SwiftUI

struct JobDetailView: View {
    let job: Job
    let sheetName: String?
    @ObservedObject var starredStore: StarredJobsStore
    @ObservedObject var applicationsStore: ApplicationsStore
    var profile: String = "spencer"
    var region: String = "uk"

    @State private var isGeneratingCV = false
    @State private var cvStartedAt = Date()
    @State private var cvResult: CVResult? = nil
    @State private var cvError: String? = nil
    @State private var showCVOptions = false
    @State private var isGeneratingCoverLetter = false
    @State private var coverLetterPdf: Data? = nil
    @State private var coverLetterError: String? = nil
    // Description fetched on demand when the scraper couldn't get it (LinkedIn rate limit)
    @State private var fetchedJD: String? = nil
    @State private var isFetchingJD = false
    @State private var fetchJDError: String? = nil
    @State private var showAnswer = false

    private var isStarred: Bool { starredStore.isStarred(job.jobId) }
    private var effectiveJD: String? { job.jd ?? fetchedJD ?? JDCache.load(for: job.jobId) }

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

                    if let applicants = job.applicantsText {
                        Label(applicants, systemImage: "person.3")
                            .font(.subheadline)
                            .foregroundColor(job.over100 ? .orange : .secondary)
                    } else if job.over100 {
                        Label("100+ applicants", systemImage: "person.3")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    }
                    if job.sponsored {
                        Label("Visa sponsorship offered", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.green)
                    } else if job.noSponsorship {
                        Label("No visa sponsorship", systemImage: "xmark.seal")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                    if let salary = job.salaryText {
                        Label(salary, systemImage: "banknote")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.teal)
                    }
                }

                // Application tracking — mark as applied, change stage, see how long ago
                applicationCard

                // Feed jobs are pure scrapes with no AI scores — hide the empty grid
                if job.hasScores {
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

                // Generate CV + Cover Letter — both require a JD
                if let jd = effectiveJD {
                    let hasCachedCV = CVCacheStore.load(for: job.jobId) != nil
                    HStack(spacing: 10) {
                        Button {
                            if hasCachedCV {
                                showCVOptions = true
                            } else {
                                generateCV(jd: jd)
                            }
                        } label: {
                            Group {
                                if isGeneratingCV {
                                    HStack(spacing: 6) {
                                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        // live seconds so a slow fallback provider doesn't look frozen
                                        TimelineView(.periodic(from: cvStartedAt, by: 1)) { context in
                                            Text("Generating… \(Int(context.date.timeIntervalSince(cvStartedAt)))s")
                                                .lineLimit(1)
                                                .monospacedDigit()
                                        }
                                    }
                                } else {
                                    Label("Generate CV", systemImage: "doc.text.fill").lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(isGeneratingCV)
                        .confirmationDialog("A CV was already generated for this job.", isPresented: $showCVOptions, titleVisibility: .visible) {
                            Button("Use Saved CV") { cvResult = CVCacheStore.load(for: job.jobId) }
                            Button("Generate New CV") { generateCV(jd: jd) }
                            Button("Cancel", role: .cancel) {}
                        }

                        Button {
                            generateCoverLetter(jd: jd, latex: CVCacheStore.load(for: job.jobId)?.latex)
                        } label: {
                            Group {
                                if isGeneratingCoverLetter {
                                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Label("Cover Letter", systemImage: "envelope.fill").lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.indigo)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(isGeneratingCoverLetter)
                    }

                    // "Why do you want to work here?" style answer, grounded in the JD + CV
                    Button {
                        showAnswer = true
                    } label: {
                        Label("Why \(job.company)?", systemImage: "bubble.left.and.text.bubble.right")
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.indigo.opacity(0.12))
                            .foregroundColor(.indigo)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if let err = cvError {
                        Text(err).font(.caption).foregroundColor(.red).multilineTextAlignment(.center)
                    }
                    if let err = coverLetterError {
                        Text(err).font(.caption).foregroundColor(.red).multilineTextAlignment(.center)
                    }
                }

                // Visa wording the scorer based the sponsorship decision on
                if let notes = job.visaNotesText, job.sponsored || job.noSponsorship {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Label(job.sponsored ? "Visa sponsorship — from the posting" : "Visa — from the posting",
                              systemImage: job.sponsored ? "checkmark.seal.fill" : "xmark.seal")
                            .font(.headline)
                            .foregroundColor(job.sponsored ? .green : .red)
                        Text(notes)
                            .font(.system(size: 14))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background((job.sponsored ? Color.green : Color.red).opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                // JD — or, when the scraper was rate-limited by LinkedIn, an on-demand fetch
                Divider()
                if let jdText = effectiveJD {
                    JDSectionView(text: jdText)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Job Description")
                            .font(.headline)
                        Text("LinkedIn blocked the scraper when this job was collected, so there's no description yet — which is also why CV and cover-letter generation are hidden.")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            fetchDescription()
                        } label: {
                            Group {
                                if isFetchingJD {
                                    HStack(spacing: 8) {
                                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        Text("Fetching…")
                                    }
                                } else {
                                    Label("Fetch description", systemImage: "arrow.down.doc")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.indigo)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(isFetchingJD)
                        if let err = fetchJDError {
                            Text(err).font(.caption).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
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
                CVPreviewView(jd: effectiveJD ?? "", jobId: job.jobId, profile: profile, result: result,
                              fileName: resumeFileName(title: job.title, company: job.company, location: job.location))
            }
        }
        .sheet(isPresented: $showAnswer) {
            if let jd = effectiveJD {
                AnswerSheet(jd: jd, company: job.company, title: job.title, latex: CVCacheStore.load(for: job.jobId)?.latex, profile: profile)
            }
        }
        .sheet(isPresented: Binding(
            get: { coverLetterPdf != nil },
            set: { if !$0 { coverLetterPdf = nil } }
        )) {
            if let pdf = coverLetterPdf {
                CoverLetterPreviewView(pdfData: pdf, jobTitle: job.title)
            }
        }
    }

    // MARK: - Application tracking

    @ViewBuilder
    private var applicationCard: some View {
        if let app = applicationsStore.application(for: job.jobId) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(app.appliedAgoText, systemImage: "paperplane.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.green)
                    Spacer()
                    Menu {
                        ForEach(applicationsStore.stages) { stage in
                            Button {
                                applicationsStore.setStage(job.jobId, stageId: stage.id)
                            } label: {
                                if stage.id == app.stageId {
                                    Label(stage.name, systemImage: "checkmark")
                                } else {
                                    Text(stage.name)
                                }
                            }
                        }
                        Divider()
                        Button(role: .destructive) {
                            applicationsStore.unmark(job.jobId)
                        } label: {
                            Label("Remove from applications", systemImage: "trash")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(applicationsStore.stageName(app.stageId))
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.indigo.opacity(0.12))
                        .foregroundColor(.indigo)
                        .clipShape(Capsule())
                    }
                }
                if let summary = applicantsSummary(app) {
                    Label(summary, systemImage: "person.3")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if app.history.count > 1 {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(app.history.suffix(4)) { change in
                            Text("\(applicationsStore.stageName(change.stageId)) · \(change.at.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            Button {
                applicationsStore.markApplied(job, region: region, sheet: sheetName)
            } label: {
                Label("Mark as applied", systemImage: "paperplane")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green.opacity(0.15))
                    .foregroundColor(.green)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    /// "31 applicants when listed · 67 when you applied"
    private func applicantsSummary(_ app: Application) -> String? {
        let listed = app.applicantsAtFetch.flatMap { $0.isEmpty ? nil : $0 }
        let applied = app.applicantsAtApply.flatMap { $0.isEmpty ? nil : $0 }
        switch (listed, applied) {
        case let (l?, a?) where l != a: return "\(l) when listed · \(a) when you applied"
        case let (l?, _): return "\(l) when listed"
        case let (nil, a?): return "\(a) when you applied"
        default: return nil
        }
    }

    private func fetchDescription() {
        isFetchingJD = true
        fetchJDError = nil
        Task {
            do {
                fetchedJD = try await JobsService.fetchJobDescription(url: job.link, profile: profile, sheet: sheetName, jobId: job.jobId)
            } catch {
                fetchJDError = error.localizedDescription
            }
            isFetchingJD = false
        }
    }

    private func generateCV(jd: String) {
        cvStartedAt = Date()
        isGeneratingCV = true
        cvError = nil
        Task {
            do {
                let result = try await CVService.generateCV(jd: jd, profile: profile)
                CVCacheStore.save(result, for: job.jobId)
                cvResult = result
            } catch {
                cvError = error.localizedDescription
            }
            isGeneratingCV = false
        }
    }

    private func generateCoverLetter(jd: String, latex: String?) {
        isGeneratingCoverLetter = true
        coverLetterError = nil
        Task {
            do {
                let pdf = try await CVService.generateCoverLetter(jd: jd, latex: latex, profile: profile)
                coverLetterPdf = pdf
            } catch {
                coverLetterError = error.localizedDescription
            }
            isGeneratingCoverLetter = false
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

// MARK: - "Why this company?" answer

private struct AnswerSheet: View {
    let jd: String
    let company: String
    let title: String
    let latex: String?
    let profile: String
    @Environment(\.dismiss) private var dismiss
    @State private var question: String
    @State private var answer: String = ""
    @State private var isGenerating = false
    @State private var error: String? = nil
    @State private var copied = false

    init(jd: String, company: String, title: String, latex: String?, profile: String) {
        self.jd = jd
        self.company = company
        self.title = title
        self.latex = latex
        self.profile = profile
        _question = State(initialValue: "What motivates you about joining \(company) and where are you in your career that makes this the right time to join us now?")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Question")
                        .font(.headline)
                    TextField("Paste the application question…", text: $question, axis: .vertical)
                        .lineLimit(2...6)
                        .font(.system(size: 14))
                        .padding(10)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Button {
                        generate()
                    } label: {
                        Group {
                            if isGenerating {
                                HStack(spacing: 8) {
                                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    Text("Writing…")
                                }
                            } else {
                                Label(answer.isEmpty ? "Generate answer" : "Regenerate", systemImage: "sparkles")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.indigo)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isGenerating || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let error {
                        Text(error).font(.caption).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
                    }

                    if !answer.isEmpty {
                        HStack {
                            Text("Answer")
                                .font(.headline)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = answer
                                copied = true
                                Task {
                                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                                    copied = false
                                }
                            } label: {
                                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                                    .font(.subheadline)
                            }
                        }
                        Text(answer)
                            .font(.system(size: 15))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Text("\(answer.split(whereSeparator: { $0.isWhitespace }).count) words" + (latex == nil ? " · based on profile background (no CV generated yet)" : " · based on the generated CV"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Why \(company)?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .task { if answer.isEmpty { generate() } }
        }
    }

    private func generate() {
        isGenerating = true
        error = nil
        Task {
            do {
                answer = try await CVService.generateAnswer(jd: jd, company: company, title: title, question: question, latex: latex, profile: profile)
            } catch {
                self.error = error.localizedDescription
            }
            isGenerating = false
        }
    }
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
