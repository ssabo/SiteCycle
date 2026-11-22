import SwiftUI
import Charts

/// Statistics "Duration Trend" section: a dot per week (mean duration of the
/// sites that ended that week), the rolling average as a line, and a badge on
/// weeks where sites ended with a problem. Logic is in `DurationTrend`.
struct DurationTrendSection: View {
    let points: [WeeklyDurationPoint]

    /// Weeks visible at once; longer histories scroll, starting at the latest week.
    private static let visibleWeeks = 26
    private static let weekSeconds: TimeInterval = 7 * 24 * 3600

    var body: some View {
        Section {
            chart
                .frame(height: 220)
                .padding(.top, 8)
        } header: {
            Text("Duration Trend")
        } footer: {
            Text("Dots: average duration of the sites that ended each week. "
                + "Line: \(DurationTrend.rollingWeeks)-week moving average. "
                + "Orange badge: how many of that week's sites had a problem.")
        }
    }

    private var chart: some View {
        Chart {
            ForEach(points) { point in
                if let rolling = point.rollingAverage, let segment = point.trendSegment {
                    LineMark(
                        x: .value("Week", point.weekStart, unit: .weekOfYear),
                        y: .value("Moving Average", rolling),
                        series: .value("Segment", segment)
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .foregroundStyle(Color.accentColor)
                }
            }
            ForEach(points) { point in
                if let average = point.averageDuration {
                    PointMark(
                        x: .value("Week", point.weekStart, unit: .weekOfYear),
                        y: .value("Weekly Average", average)
                    )
                    .symbolSize(point.problemSiteCount > 0 ? 60 : 36)
                    .foregroundStyle(point.problemSiteCount > 0 ? Color.orange : Color.secondary)
                    .annotation(position: .top, spacing: 2) {
                        if point.problemSiteCount > 0 {
                            problemBadge(point.problemSiteCount)
                        }
                    }
                    .accessibilityLabel(Text("Week of \(point.weekStart.formatted(date: .abbreviated, time: .omitted))"))
                    .accessibilityValue(Text(accessibilityValue(point, average: average)))
                }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxisLabel("Hours")
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: Double(min(points.count, Self.visibleWeeks)) * Self.weekSeconds)
        .chartScrollPosition(initialX: initialScrollWeek)
    }

    /// Leading edge of the initially visible weeks, so the latest week is in view.
    private var initialScrollWeek: Date {
        let index = max(points.count - Self.visibleWeeks, 0)
        return points.indices.contains(index) ? points[index].weekStart : Date()
    }

    private func problemBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(minWidth: 16, minHeight: 16)
            .background(Capsule().fill(Color.orange))
    }

    private func accessibilityValue(_ point: WeeklyDurationPoint, average: Double) -> String {
        var parts = [
            "average \(formatHours(average))",
            point.siteCount == 1 ? "1 site" : "\(point.siteCount) sites"
        ]
        if point.problemSiteCount > 0 {
            parts.append("\(point.problemSiteCount) with a problem")
        }
        if let rolling = point.rollingAverage {
            parts.append("\(DurationTrend.rollingWeeks)-week average \(formatHours(rolling))")
        }
        return parts.joined(separator: ", ")
    }

    private func formatHours(_ hours: Double) -> String {
        String(format: "%.1fh", hours)
    }
}
