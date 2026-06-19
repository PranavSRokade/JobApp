import Foundation

func parseScrapeDate(_ sheetName: String) -> Date? {
    let pattern = /^(\d{2})-(\d{2})(AM|PM)_(\d{2})-([A-Za-z]{3})-(\d{2})$/
    guard let m = try? pattern.wholeMatch(in: sheetName) else { return nil }
    let (_, hh, mm, ampm, dd, monthAbbr, yy) = m.output

    var hour = Int(hh) ?? 0
    if ampm == "PM" && hour != 12 { hour += 12 }
    if ampm == "AM" && hour == 12 { hour = 0 }

    let df = DateFormatter()
    df.dateFormat = "MMM"
    guard let monthDate = df.date(from: String(monthAbbr)) else { return nil }
    let month = Calendar.current.component(.month, from: monthDate)

    var comps = DateComponents()
    comps.year   = 2000 + (Int(yy) ?? 0)
    comps.month  = month
    comps.day    = Int(dd) ?? 0
    comps.hour   = hour
    comps.minute = Int(mm) ?? 0
    comps.second = 0
    return Calendar.current.date(from: comps)
}

func parseAgeTextToMinutes(_ text: String) -> Int? {
    let lower = text.lowercased()
    if lower.contains("just now") { return 0 }
    let units: [(String, Int)] = [
        ("month", 43_200), ("week", 10_080),
        ("day", 1_440), ("hour", 60), ("minute", 1),
    ]
    let digits = lower.components(separatedBy: CharacterSet.decimalDigits.inverted)
        .compactMap(Int.init).first ?? 1
    for (unit, factor) in units {
        if lower.contains(unit) { return digits * factor }
    }
    return nil
}

func formatMinutes(_ total: Int) -> String {
    switch total {
    case ..<1:      return "Just now"
    case ..<60:     return "\(total)m ago"
    case ..<1_440:  return "\(total / 60)h ago"
    case ..<10_080: return "\(total / 1_440)d ago"
    case ..<43_200: return "\(total / 10_080)w ago"
    default:        return "\(total / 43_200)mo ago"
    }
}

func actualAge(sheetName: String?, ageText: String) -> String {
    guard
        let sheetName,
        let scrapeDate = parseScrapeDate(sheetName),
        let ageAtScrapeMinutes = parseAgeTextToMinutes(ageText)
    else { return ageText }

    let jobPostedAt = scrapeDate.addingTimeInterval(-Double(ageAtScrapeMinutes) * 60)
    let elapsed = Int(Date().timeIntervalSince(jobPostedAt) / 60)
    return formatMinutes(max(0, elapsed))
}
