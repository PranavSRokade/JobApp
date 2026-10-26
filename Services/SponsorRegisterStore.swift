import Foundation
import Combine

// MARK: - UK Home Office register of licensed sponsors (Worker routes)
// Pure name matching against the gov.uk CSV — no AI anywhere. The register is stored on
// device, parsed in the background, and auto-updated from gov.uk when a newer sheet appears.

struct SponsorCompany: Codable, Hashable {
    let name: String
    let town: String
    let county: String
    let licences: [String] // e.g. "Skilled Worker — Worker (A rating)"

    var place: String {
        [town, county].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

struct SponsorMatch: Identifiable {
    let id = UUID()
    let company: SponsorCompany
    let exact: Bool
}

struct SponsorRegisterMeta: Codable {
    var sheetDate: String // "2026-10-23" from the gov.uk filename
    var importedAt: Date
    var count: Int
    var source: String // "gov.uk" or "manual import"
    var lastCheckedAt: Date?
}

/// Immutable parsed register — safe to hand to background lookups.
final class SponsorRegisterData: @unchecked Sendable {
    let companies: [SponsorCompany]
    let index: [String: [Int32]] // stripped-normalized name → company indexes

    init(companies: [SponsorCompany], index: [String: [Int32]]) {
        self.companies = companies
        self.index = index
    }
}

@MainActor
final class SponsorRegisterStore: ObservableObject {
    static let shared = SponsorRegisterStore()

    @Published private(set) var meta: SponsorRegisterMeta?
    @Published private(set) var isLoading = false // parsing the stored CSV
    @Published private(set) var isChecking = false // talking to gov.uk
    @Published private(set) var isImporting = false
    @Published var lastCheckResult: String?

    // Published so list rows light up their sponsor shields the moment parsing finishes
    @Published private(set) var data: SponsorRegisterData?
    private var loadTask: Task<Void, Never>?
    // companyName → exact-hit, so scrolling doesn't re-normalize the same names over and over
    private var exactCache: [String: Bool] = [:]

    private static let registerPage = "https://www.gov.uk/government/publications/register-of-licensed-sponsors-workers"
    private static let autoCheckInterval: TimeInterval = 3 * 24 * 3600 // gov.uk republishes every few weeks

    /// Sheet older than this is flagged in the UI — the "upload a new sheet" reminder.
    var isStale: Bool {
        guard let meta else { return true }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: meta.sheetDate) else { return false }
        return Date().timeIntervalSince(d) > 45 * 24 * 3600
    }

    private init() {
        loadTask = Task { [weak self] in
            await self?.loadFromDisk()
            await self?.checkForUpdate(force: false)
        }
    }

    // MARK: Lookup

    /// Synchronous exact-hit check for list rows: O(1) dictionary lookup, cached per name.
    /// Close matches are deliberately excluded here — they only show in the detail view.
    func hasSponsor(company: String) -> Bool {
        guard let data else { return false }
        if let cached = exactCache[company] { return cached }
        let key = Self.stripped(Self.normalize(company))
        let hit = key.count >= 3 && data.index[key] != nil
        exactCache[company] = hit
        return hit
    }

    /// Matches a job's employer name against the register. Exact = normalized-name hit
    /// (legal suffixes and "T/A …" aliases handled); otherwise close word-prefix matches.
    func match(company: String) async -> [SponsorMatch] {
        _ = await loadTask?.value
        guard let data else { return [] }
        let name = company
        return await Task.detached(priority: .userInitiated) {
            Self.lookup(name, in: data)
        }.value
    }

    // MARK: Import

    func importCSV(_ csv: Data, sheetDate: String, source: String) async {
        isImporting = true
        defer { isImporting = false }
        let parsed = await Task.detached(priority: .userInitiated) { Self.parse(csv) }.value
        guard parsed.companies.count > 1000 else {
            lastCheckResult = "That file doesn't look like the sponsor register (only \(parsed.companies.count) companies found)"
            return
        }
        data = parsed
        exactCache = [:]
        meta = SponsorRegisterMeta(sheetDate: sheetDate, importedAt: Date(), count: parsed.companies.count, source: source, lastCheckedAt: meta?.lastCheckedAt)
        lastCheckResult = "Imported \(parsed.companies.count.formatted()) companies (sheet \(sheetDate))"
        persist(csv: csv)
    }

    /// Manual import from the Files picker — takes the date from the filename when present.
    func importPickedFile(data csv: Data, filename: String) async {
        let date = Self.firstMatch(#"\d{4}-\d{2}-\d{2}"#, in: filename) ?? Self.todayString()
        await importCSV(csv, sheetDate: date, source: "manual import")
    }

    // MARK: Auto-update from gov.uk

    func checkForUpdate(force: Bool) async {
        if !force {
            if let checked = meta?.lastCheckedAt, Date().timeIntervalSince(checked) < Self.autoCheckInterval, data != nil { return }
        }
        isChecking = true
        defer { isChecking = false }
        do {
            var req = URLRequest(url: URL(string: Self.registerPage)!)
            req.timeoutInterval = 30
            let (pageData, _) = try await URLSession.shared.data(for: req)
            let html = String(decoding: pageData, as: UTF8.self)
            guard let csvURL = Self.firstMatch(#"https://assets\.publishing\.service\.gov\.uk/media/[^"]+\.csv"#, in: html),
                  let url = URL(string: csvURL) else {
                throw URLError(.cannotParseResponse)
            }
            let sheetDate = Self.firstMatch(#"\d{4}-\d{2}-\d{2}"#, in: csvURL) ?? Self.todayString()

            markChecked()
            if let current = meta?.sheetDate, current >= sheetDate, data != nil {
                if force { lastCheckResult = "Already on the latest sheet (\(current))" }
                return
            }

            var dl = URLRequest(url: url)
            dl.timeoutInterval = 120
            let (csv, _) = try await URLSession.shared.data(for: dl)
            await importCSV(csv, sheetDate: sheetDate, source: "gov.uk")
        } catch {
            if force { lastCheckResult = "Update check failed: \(error.localizedDescription)" }
        }
    }

    private func markChecked() {
        if meta != nil {
            meta?.lastCheckedAt = Date()
            persistMetaOnly()
        }
    }

    // MARK: Persistence (raw CSV + meta JSON in Application Support)

    nonisolated private static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("SponsorRegister", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    nonisolated private static var csvURL: URL { dir.appendingPathComponent("register.csv") }
    nonisolated private static var metaURL: URL { dir.appendingPathComponent("meta.json") }

    private func persist(csv: Data) {
        let m = meta
        Task.detached(priority: .utility) {
            try? csv.write(to: Self.csvURL, options: .atomic)
            if let m, let encoded = try? JSONEncoder().encode(m) {
                try? encoded.write(to: Self.metaURL, options: .atomic)
            }
        }
    }

    private func persistMetaOnly() {
        if let m = meta, let encoded = try? JSONEncoder().encode(m) {
            try? encoded.write(to: Self.metaURL, options: .atomic)
        }
    }

    private func loadFromDisk() async {
        guard let metaData = try? Data(contentsOf: Self.metaURL),
              let storedMeta = try? JSONDecoder().decode(SponsorRegisterMeta.self, from: metaData),
              let csv = try? Data(contentsOf: Self.csvURL) else { return }
        isLoading = true
        let parsed = await Task.detached(priority: .userInitiated) { Self.parse(csv) }.value
        data = parsed
        exactCache = [:]
        meta = storedMeta
        isLoading = false
    }

    // MARK: - Pure matching logic (nonisolated, tested from the command line)

    nonisolated static func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    nonisolated static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let r = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[r])
    }

    /// "C. Bechstein Hall Limited" → "c bechstein hall limited"
    nonisolated static func normalize(_ s: String) -> String {
        var t = s.lowercased()
        t = t.replacingOccurrences(of: "&", with: " and ")
        t = t.replacingOccurrences(of: #"[^a-z0-9 ]"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Drops legal suffixes so "Yoto Ltd" and "Yoto Limited" meet in the middle.
    nonisolated static func stripped(_ normalized: String) -> String {
        var words = normalized.split(separator: " ").map(String.init)
        let suffixes: Set<String> = ["ltd", "limited", "plc", "llp", "llc", "inc", "incorporated", "co", "company", "uk", "holdings", "group", "gb"]
        while let last = words.last, suffixes.contains(last), words.count > 1 { words.removeLast() }
        if words.first == "the", words.count > 1 { words.removeFirst() }
        return words.joined(separator: " ")
    }

    /// "BRANOS OXFORD LTD T/A LILO" → the legal and the trading name are both indexed.
    nonisolated static func splitTradingNames(_ raw: String) -> [String] {
        let pattern = #"(?i)\s+(?:t/a|t\.a\.|trading\s+as)\s+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [raw] }
        let ns = raw as NSString
        let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return [raw] }
        var parts: [String] = [raw]
        var last = 0
        for m in matches {
            parts.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        parts.append(ns.substring(from: last))
        return parts
    }

    /// RFC 4180-ish CSV parse over raw bytes — handles quoted fields with commas, and the
    /// register's stray spaces / repeated rows (one row per licence → grouped per company).
    nonisolated static func parse(_ csvData: Data) -> SponsorRegisterData {
        let bytes = [UInt8](csvData)
        var fields: [String] = []
        var field: [UInt8] = []
        var inQuotes = false
        var rowNumber = 0

        struct Agg { var town: String; var county: String; var licences: [String]; let order: Int }
        var byName: [String: Agg] = [:]
        var order = 0

        func clean(_ s: String) -> String {
            s.trimmingCharacters(in: CharacterSet(charactersIn: " \t,"))
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        }

        func endField() {
            fields.append(String(decoding: field, as: UTF8.self))
            field.removeAll(keepingCapacity: true)
        }

        func endRow() {
            defer { fields.removeAll(keepingCapacity: true) }
            rowNumber += 1
            if rowNumber == 1 { return } // header
            guard fields.count >= 5 else { return }
            let name = clean(fields[0])
            guard !name.isEmpty else { return }
            let town = clean(fields[1])
            let county = clean(fields[2])
            let licence = "\(clean(fields[4])) — \(clean(fields[3]))"
            if var cur = byName[name] {
                if !cur.licences.contains(licence) { cur.licences.append(licence) }
                if cur.town.isEmpty { cur.town = town }
                if cur.county.isEmpty { cur.county = county }
                byName[name] = cur
            } else {
                byName[name] = Agg(town: town, county: county, licences: [licence], order: order)
                order += 1
            }
        }

        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if inQuotes {
                if b == 0x22 {
                    if i + 1 < bytes.count && bytes[i + 1] == 0x22 {
                        field.append(0x22)
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(b)
                }
            } else {
                switch b {
                case 0x22: inQuotes = true
                case 0x2C: endField()
                case 0x0A: endField(); endRow()
                case 0x0D: break
                default: field.append(b)
                }
            }
            i += 1
        }
        if !field.isEmpty || !fields.isEmpty { endField(); endRow() }

        let companies = byName
            .map { (name: $0.key, agg: $0.value) }
            .sorted { $0.agg.order < $1.agg.order }
            .map { SponsorCompany(name: $0.name, town: $0.agg.town, county: $0.agg.county, licences: $0.agg.licences) }

        var index: [String: [Int32]] = [:]
        index.reserveCapacity(companies.count * 2)
        for (i, company) in companies.enumerated() {
            for variant in splitTradingNames(company.name) {
                let key = stripped(normalize(variant))
                guard key.count >= 3 else { continue }
                if index[key]?.contains(Int32(i)) != true {
                    index[key, default: []].append(Int32(i))
                }
            }
        }
        return SponsorRegisterData(companies: companies, index: index)
    }

    nonisolated static func lookup(_ companyName: String, in data: SponsorRegisterData) -> [SponsorMatch] {
        let key = stripped(normalize(companyName))
        guard key.count >= 3 else { return [] }

        if let hits = data.index[key] {
            return hits.prefix(3).map { SponsorMatch(company: data.companies[Int($0)], exact: true) }
        }

        // Close matches: word-boundary prefix either way ("checkout" ↔ "checkout com"),
        // never bare substrings ("apple" must not match "applegate farm").
        guard key.count >= 5 else { return [] }
        let keySp = key + " "
        var candidates: [(idx: Int32, distance: Int)] = []
        for (k, hits) in data.index {
            guard min(k.count, key.count) >= 5 else { continue }
            if k.hasPrefix(keySp) || keySp.hasPrefix(k + " ") {
                for h in hits { candidates.append((h, abs(k.count - key.count))) }
            }
        }
        return candidates
            .sorted { $0.distance < $1.distance }
            .prefix(3)
            .map { SponsorMatch(company: data.companies[Int($0.idx)], exact: false) }
    }
}
