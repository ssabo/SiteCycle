import Foundation

/// Shared formatting for a single site's duration, so the same site reads the
/// same in History and on the confirmation sheet. (Statistics deliberately
/// uses one decimal, e.g. "31.4h", for medians and percentiles.)
enum DurationFormat {
    /// "31h 24m", "31h", or "45m".
    static func hoursMinutes(_ hours: Double) -> String {
        let wholeHours = Int(hours)
        let minutes = Int((hours - Double(wholeHours)) * 60)
        if wholeHours > 0 && minutes > 0 {
            return "\(wholeHours)h \(minutes)m"
        } else if wholeHours > 0 {
            return "\(wholeHours)h"
        } else {
            return "\(minutes)m"
        }
    }
}
