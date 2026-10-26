import SwiftUI

// MARK: - Nightly scraper status (the pipeline runs on the Cloudflare worker, not GitHub)

private struct PipelineStatus: Decodable {
    let phase: String
    let runDate: String?
    let region: String?
    let searchesDone: Int?
    let searchTotal: Int?
    let candidates: Int?
    let queue: Int?
    let appended: Int?
    let sponsored: Int?
    let unscored: Int?
    let tab: String?
    let startedAt: String?
    let updatedAt: String?
    let summaries: [String]?
    let log: [String]?
}

struct PipelineStatusView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var status: PipelineStatus?
    @State private var error: String?
    @State private var isStarting = false
    @State private var confirmRun = false

    private let base = "https://job-worker.pranavrokade.workers.dev/api/pipeline"

    var body: some View {
        NavigationStack {
            List {
                if let status {
                    Section {
                        HStack {
                            Text("Phase").font(.system(size: 14))
                            Spacer()
                            Text(phaseLabel(status.phase))
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(phaseColor(status.phase).opacity(0.15))
                                .foregroundColor(phaseColor(status.phase))
                                .clipShape(Capsule())
                        }
                        if let region = status.region, status.phase != "never-run" {
                            row("Market", region.uppercased())
                        }
                        if let done = status.searchesDone, let total = status.searchTotal, status.phase == "scrape" {
                            row("Searches", "\(done)/\(total)")
                        }
                        if let queue = status.queue, status.phase == "process" {
                            row("Jobs left to process", "\(queue)")
                        }
                        if let appended = status.appended {
                            row("Saved to sheet", "\(appended)")
                        }
                        if let tab = status.tab {
                            row("Tab", tab)
                        }
                        if let updated = status.updatedAt {
                            row("Last activity", friendlyTime(updated))
                        }
                    } header: {
                        Text("Tonight's run" + (status.runDate.map { " — \($0)" } ?? ""))
                    }

                    if let summaries = status.summaries, !summaries.isEmpty {
                        Section("Summary") {
                            ForEach(summaries, id: \.self) { s in
                                Text(s).font(.system(size: 13))
                            }
                        }
                    }

                    if let log = status.log, !log.isEmpty {
                        Section("Log") {
                            ForEach(Array(log.enumerated().reversed()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else if let error {
                    ContentUnavailableView("Can't reach the worker", systemImage: "wifi.exclamationmark", description: Text(error))
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading status…").font(.system(size: 14)).foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Scraper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        confirmRun = true
                    } label: {
                        if isStarting { ProgressView() } else { Label("Run now", systemImage: "play.fill") }
                    }
                    .disabled(isStarting || status?.phase == "scrape" || status?.phase == "process" || status?.phase == "dedupe")
                }
            }
            .confirmationDialog("Start a full scrape run now?", isPresented: $confirmRun, titleVisibility: .visible) {
                Button("Start run") { Task { await startRun() } }
                Button("Cancel", role: .cancel) {}
            }
            .refreshable { await load() }
            .task {
                await load()
                // live-ish updates while the sheet is open
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 20_000_000_000)
                    await load()
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 14))
            Spacer()
            Text(value).font(.system(size: 14)).foregroundColor(.secondary).lineLimit(1)
        }
    }

    private func phaseLabel(_ phase: String) -> String {
        switch phase {
        case "scrape": return "Scraping"
        case "dedupe": return "Deduplicating"
        case "process": return "Fetching + scoring"
        case "done": return "Done"
        case "error": return "Stopped — errors"
        case "never-run": return "Not run yet"
        default: return phase
        }
    }

    private func phaseColor(_ phase: String) -> Color {
        switch phase {
        case "done": return .green
        case "error": return .red
        case "never-run": return .secondary
        default: return .indigo
        }
    }

    private func friendlyTime(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter.cached.date(from: iso) else { return iso }
        let mins = Int(Date().timeIntervalSince(date) / 60)
        if mins < 1 { return "just now" }
        if mins < 60 { return "\(mins)m ago" }
        return "\(mins / 60)h \(mins % 60)m ago"
    }

    private func load() async {
        guard let url = URL(string: "\(base)/status") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            status = try JSONDecoder().decode(PipelineStatus.self, from: data)
            error = nil
        } catch {
            if status == nil { self.error = error.localizedDescription }
        }
    }

    private func startRun() async {
        isStarting = true
        defer { isStarting = false }
        guard let url = URL(string: "\(base)/run") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        _ = try? await URLSession.shared.data(for: req)
        await load()
    }
}

private extension ISO8601DateFormatter {
    static let cached: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
