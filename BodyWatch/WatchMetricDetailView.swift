//
//  WatchMetricDetailView.swift
//  BodyWatch
//
//  Immersive drill-down from a dashboard card (or a tapped complication): the
//  metric tint washes the whole screen, the title sits top-right, the recent-
//  week chart sits below it, and the current value reads large at the
//  bottom-left — followed, for Readiness and Training Load, by the status level
//  beside it ("85 · HIGH"). The tint fill is the page's own background so it
//  slides with the vertical pager, giving a smooth color transition between
//  metrics. Display-only: it reads the `weekly` series and `statusBand` the
//  iPhone baked into the pushed snapshot (no watch compute).
//
//  Watch-only: not compiled into the iOS `Body` target.
//

import SwiftUI

struct WatchMetricDetailView: View {
    let metric: WatchMetric
    /// The day the metric's weekly series ends on — the snapshot's generation
    /// date — so a cached snapshot shown on a later day still labels its days
    /// against when the data was built, not against the current date.
    var referenceDate: Date = Date()

    private var tintColor: Color { Color(metric.resolvedTint) }

    private var weekly: [Double?]? {
        guard let weekly = metric.weekly, weekly.contains(where: { $0 != nil }) else { return nil }
        return weekly
    }

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                titleRow

                if let weekly {
                    WatchSparklineView(
                        values: weekly,
                        tint: tintColor,
                        band: metric.statusBand,
                        currentValue: metric.weeklyCurrentValue,
                        dayLabels: weekdayLabels(count: weekly.count)
                    )
                    .frame(height: 86)
                    .padding(.top, 4)
                } else {
                    Text("No recent data yet")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 16)
                }

                Spacer(minLength: 6)

                valueRow
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Pieces

    private var titleRow: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(metric.title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(tintColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// Big current value at the bottom-left; for banded metrics the status level
    /// sits beside it, dot-separated ("85 · HIGH" / "1.23 · OPTIMAL").
    private var valueRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(metric.displayValue)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            if !metric.unit.isEmpty {
                Text(metric.unit)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            if let label = metric.statusBand?.label {
                Text("·")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                Text(label.uppercased())
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(tintColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            Spacer(minLength: 0)
        }
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [tintColor.opacity(0.45), Color.black],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Two-letter weekday abbreviations for the `count` days ending on
    /// `referenceDate` (oldest → newest), aligned with the chart's day slots.
    private func weekdayLabels(count: Int) -> [String] {
        let calendar = Calendar.current
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let endDay = calendar.startOfDay(for: referenceDate)
        return (0..<count).map { offset in
            let day = calendar.date(byAdding: .day, value: offset - (count - 1), to: endDay) ?? endDay
            let weekday = calendar.component(.weekday, from: day)
            return String(symbols[(weekday - 1) % symbols.count].prefix(2))
        }
    }
}

#Preview("Training Load (banded)") {
    NavigationStack {
        WatchMetricDetailView(metric: WatchMetric(
            kind: WatchMetricKindKey.trainingLoad,
            title: "Load Ratio",
            displayValue: "1.23",
            unit: "",
            score: nil,
            fillFraction: 0.62,
            rawValue: 1.23,
            rangeMin: 0,
            rangeMax: 2,
            tint: WatchMetricColor(red: 0.10, green: 0.82, blue: 0.20),
            weekly: [0.95, 1.30, 1.05, 0.78, 1.32, 1.10, 1.23],
            statusBand: WatchStatusBand(min: 0.8, max: 1.3, label: "Optimal")
        ))
    }
}

#Preview("Heart Rate") {
    NavigationStack {
        WatchMetricDetailView(metric: WatchMetric(
            kind: WatchMetricKindKey.heartRate,
            title: "Heart Rate",
            displayValue: "62",
            unit: "bpm",
            score: nil,
            fillFraction: 0.45,
            rawValue: 62,
            rangeMin: 54,
            rangeMax: 72,
            weekly: [58, 64, nil, 55, 72, 61, 62]
        ))
    }
}
