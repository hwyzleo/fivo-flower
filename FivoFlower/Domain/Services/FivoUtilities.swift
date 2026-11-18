import Foundation

// MARK: - Utilities

enum FivoDate {
    static var defaultCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = .current
        return calendar
    }

    static func startOfDay(_ date: Date, calendar: Calendar = defaultCalendar) -> Date {
        calendar.startOfDay(for: date)
    }

    static func isSameDay(_ lhs: Date, _ rhs: Date, calendar: Calendar = defaultCalendar) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    /// 包含首尾两天的自然日数量；开始当天计为第 1 天。
    static func inclusiveDays(from start: Date, through end: Date, calendar: Calendar = defaultCalendar) -> Int {
        let from = startOfDay(start, calendar: calendar)
        let to = startOfDay(end, calendar: calendar)
        let diff = calendar.dateComponents([.day], from: from, to: to).day ?? 0
        return max(1, diff + 1)
    }

    /// 两个日期之间的自然日差（不含起始日）。
    static func dayDifference(from start: Date, to end: Date, calendar: Calendar = defaultCalendar) -> Int {
        let from = startOfDay(start, calendar: calendar)
        let to = startOfDay(end, calendar: calendar)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    static func anniversaryYears(from start: Date, to end: Date, calendar: Calendar = defaultCalendar) -> Int {
        let from = startOfDay(start, calendar: calendar)
        let to = startOfDay(end, calendar: calendar)
        guard to >= from else { return 0 }
        var years = calendar.dateComponents([.year], from: from, to: to).year ?? 0
        // 逐周年校验，确保闰日与月末边界按日历日计算
        while years > 0 {
            if let anniversary = calendar.date(byAdding: .year, value: years, to: from),
               startOfDay(anniversary, calendar: calendar) > to {
                years -= 1
            } else {
                break
            }
        }
        return max(0, years)
    }

    static func monthStart(_ date: Date, calendar: Calendar = defaultCalendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? startOfDay(date, calendar: calendar)
    }

    static func isFutureDay(_ date: Date, now: Date, calendar: Calendar = defaultCalendar) -> Bool {
        startOfDay(date, calendar: calendar) > startOfDay(now, calendar: calendar)
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = defaultCalendar
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = defaultCalendar
        formatter.timeZone = .current
        formatter.dateFormat = "M 月 d 日"
        return formatter
    }()

    static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = defaultCalendar
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static let yearMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = defaultCalendar
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy 年 M 月"
        return formatter
    }()

    static func day(_ date: Date) -> String { dayFormatter.string(from: date) }
    static func dateTime(_ date: Date) -> String { dateTimeFormatter.string(from: date) }
    static func shortDay(_ date: Date) -> String { shortDayFormatter.string(from: date) }
}

enum FivoMoney {
    static func round2(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }

    static func parse(_ text: String) -> Decimal? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: "元", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        guard value >= 0 else { return nil }
        guard value == round2(value) else { return nil }
        return value
    }

    static func plainString(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: round2(value))
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: number) ?? "\(number)"
    }

    static func display(_ value: Decimal, currency: String = "CNY") -> String {
        let number = NSDecimalNumber(decimal: round2(value))
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: number) ?? "¥\(number)"
    }

    static func signedDisplay(_ value: Decimal) -> String {
        let prefix = value < 0 ? "−" : ""
        return prefix + display(abs(value))
    }
}

enum FivoCSV {
    static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    static func line(_ values: [String]) -> String {
        values.map(escape).joined(separator: ",")
    }
}
