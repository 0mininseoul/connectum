import Foundation

enum ConnectumDateParser {
    static func parse(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        for candidate in candidates(for: trimmed) {
            if let date = parseISO8601(candidate) {
                return date
            }
        }

        for format in fallbackFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        return nil
    }

    private static func candidates(for value: String) -> [String] {
        var values = orderedUnique([value, normalizedTimezoneSuffix(value)])

        if let postgres = normalizePostgresSeparator(value) {
            values.append(contentsOf: orderedUnique([postgres, normalizedTimezoneSuffix(postgres)]))
        }

        let withDefaultTimezone = values.flatMap { candidate -> [String] in
            guard candidate.contains("T"), !hasTimezoneSuffix(candidate) else {
                return [candidate]
            }
            return [candidate, "\(candidate)Z"]
        }

        return orderedUnique(withDefaultTimezone)
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: value) { return date }

        let dateOnly = ISO8601DateFormatter()
        dateOnly.formatOptions = [.withFullDate]
        return dateOnly.date(from: value)
    }

    private static func normalizePostgresSeparator(_ value: String) -> String? {
        guard let space = value.firstIndex(of: " ") else { return nil }
        var normalized = value
        normalized.replaceSubrange(space...space, with: "T")
        return normalized.replacingOccurrences(of: " ", with: "")
    }

    private static func normalizedTimezoneSuffix(_ value: String) -> String {
        if let range = value.range(of: #"[+-]\d{2}$"#, options: .regularExpression) {
            return "\(value[..<range.lowerBound])\(value[range]):00"
        }
        if let range = value.range(of: #"[+-]\d{4}$"#, options: .regularExpression) {
            let suffix = value[range]
            return "\(value[..<range.lowerBound])\(suffix.prefix(3)):\(suffix.suffix(2))"
        }
        return value
    }

    private static func hasTimezoneSuffix(_ value: String) -> Bool {
        value.hasSuffix("Z")
            || value.range(of: #"[+-]\d{2}(:?\d{2})?$"#, options: .regularExpression) != nil
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static let fallbackFormats = [
        "yyyy-MM-dd HH:mm:ss.SSSSSS",
        "yyyy-MM-dd HH:mm:ss.SSS",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd"
    ]
}
