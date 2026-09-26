//
//  BodySleepDebtCard.swift
//  Body
//
//  The Sleep page's Sleep Debt card: the 14 night debt through the latest
//  night, the line of the debt after each of the last 14 nights, and the
//  page's selected night broken into what was slept, what was needed, and the
//  sleep goal beside it. About Sleep Debt explains the bands and which night the
//  total runs through.
//

import SwiftUI

struct BodySleepDebtCard: View {
    let model: SleepDebtChartModel
    /// The page's selected sleep day; the night row always describes it.
    let selectedDay: Date
    let tint: Color
    /// Where a hold on the chart publishes its callout; nil in previews.
    var floatingCallout: BodyChartFloatingCalloutState? = nil
    /// Sleep Debt is a Body Pro feature: locked, the card keeps its title and
    /// shows a lock and an unlock button in place of the debt, the chart, and
    /// the night row, and `onUnlock` opens the paywall.
    var isLocked = false
    var onUnlock: () -> Void = {}
    let onSelectDay: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if isLocked {
                lockedBody
            } else if model.debt == nil {
                Text("Not enough sleep data yet")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                BodySleepDebtChart(
                    nights: model.chartNights,
                    selectedDay: selectedDay,
                    color: tint,
                    floatingCallout: floatingCallout,
                    onSelectDay: onSelectDay
                )
                .frame(height: BodyHealthDetailChartLayout.standardHeight)

                if let night = model.night(on: selectedDay) {
                    Divider()

                    nightRow(night)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(translucent: true)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Sleep Debt")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Spacer(minLength: 12)

            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
            } else if let debt = model.debt {
                BodyAnimatedMetricValueText(
                    value: BodyValueFormat.durationText(for: debt),
                    fontSize: 22,
                    color: .secondary,
                    minimumScaleFactor: 0.75
                )
                .multilineTextAlignment(.trailing)
            }
        }
    }

    private var lockedBody: some View {
        VStack(spacing: 12) {
            Text("See the sleep you missed over the last 14 nights and how much you need.")
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onUnlock) {
                Text("Unlock Body Pro")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.blue, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private func nightRow(_ night: SleepDebtNight) -> some View {
        let sleptText = night.actualDuration.map(BodyValueFormat.sleepDurationText(for:)) ?? "--"
        // The need shows as a placeholder while the sleep goal stands in for
        // it; the goal still sets the debt behind it.
        let needText = night.isNeedLearned ? BodyValueFormat.durationText(for: night.needDuration) : Self.placeholder
        let goalText = BodyValueFormat.durationText(for: model.sleepGoal)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                nightValue(title: "Slept", value: sleptText)
                nightValue(title: "Need", value: needText)
                nightValue(title: "Goal", value: goalText)
            }

            if let adjustmentText = adjustmentText(for: night) {
                Text(adjustmentText)
                    .font(.system(.footnote, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.learnedNeed == nil {
                Text("Need uses your sleep goal until 28 nights are recorded")
                    .font(.system(.footnote, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if night.debtAfterNight != nil, night.recordedNightCount < SleepDebtChartModel.windowNightCount {
                Text("Based on \(night.recordedNightCount) of 14 nights")
                    .font(.system(.footnote, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Shown in place of the need until it is learned.
    static let placeholder = String(localized: "--h --m")

    /// What the need adds on top of the base need, or nil when it adds nothing.
    private func adjustmentText(for night: SleepDebtNight) -> String? {
        let trainingText = BodyValueFormat.durationText(for: night.trainingAdjustment)
        let hrvText = BodyValueFormat.durationText(for: night.hrvAdjustment)
        switch (night.trainingAdjustment > 0, night.hrvAdjustment > 0) {
        case (true, true):
            return String(localized: "Need includes \(trainingText) for training and \(hrvText) for low HRV")
        case (true, false):
            return String(localized: "Need includes \(trainingText) for training")
        case (false, true):
            return String(localized: "Need includes \(hrvText) for low HRV")
        case (false, false):
            return nil
        }
    }

    private func nightValue(title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(.caption, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(value)
                .font(.system(.callout, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .bodyLegendNumberFlip(value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A sample night history: `shortfallMinutes(daysAgo)` is how far each night
/// fell short of the 8 hour goal (negative for longer nights, nil for none).
/// `trainingDaysAgo` and `lowHRVDaysAgo` mark the days whose heavier training
/// or low sleep HRV raises the next night's need.
private func previewSleepDebtCard(
    selectedDaysAgo: Int = 0,
    trainingDaysAgo: Set<Int> = [2, 9],
    lowHRVDaysAgo: Set<Int> = [1, 9],
    learnedNeed: TimeInterval? = 8 * 3_600,
    shortfallMinutes: (Int) -> Double?
) -> some View {
    let calendar = Calendar.bodyGregorian
    let now = Date()
    let goal: TimeInterval = 8 * 3_600
    let days = SleepHistorySnapshot.datePickerDates(
        endingAt: now, dayCount: SleepDebtChartModel.entryDayCount, calendar: calendar
    )
    let entries = days.enumerated().map { index, day in
        let daysAgo = days.count - 1 - index
        return SleepDebtChartModel.Entry(
            day: day,
            duration: shortfallMinutes(daysAgo).map { goal - $0 * 60 },
            trainingLoadRatio: trainingDaysAgo.contains(daysAgo) ? 1.35 : nil,
            hrvZScore: lowHRVDaysAgo.contains(daysAgo) ? -1.8 : nil
        )
    }
    let selectedDay = calendar.date(byAdding: .day, value: -selectedDaysAgo, to: calendar.startOfDay(for: now)) ?? now

    return ScrollView {
        BodySleepDebtCard(
            model: SleepDebtChartModel.make(entries: entries, sleepGoal: goal, learnedNeed: learnedNeed),
            selectedDay: selectedDay,
            tint: Color(red: 0.20, green: 0.72, blue: 1.00),
            onSelectDay: { _ in }
        )
        .padding(16)
    }
}

#Preview("Populated") {
    previewSleepDebtCard { daysAgo in
        [45, 70, -30, 20, 90, 0, 35, -60, 50, 80, 15, 40, 65, 25][daysAgo % 14]
    }
}

#Preview("Bands") {
    // Oldest first, the debt climbs through 2 and 4 hours, falls back under 2,
    // and ends moderate, so every band color and blend between them shows.
    previewSleepDebtCard(trainingDaysAgo: [], lowHRVDaysAgo: []) { daysAgo in
        daysAgo < 14 ? [90, -30, -90, -90, -90, -30, 60, 60, 60, 60, 60, 30, 30, 30][daysAgo] : 0
    }
}

#Preview("Older night selected") {
    previewSleepDebtCard(selectedDaysAgo: 20) { daysAgo in
        Double((daysAgo * 37) % 110) - 25
    }
}

#Preview("Missing night selected") {
    previewSleepDebtCard(selectedDaysAgo: 4) { daysAgo in
        [4, 5].contains(daysAgo) ? nil : 55
    }
}

#Preview("Sparse") {
    previewSleepDebtCard(learnedNeed: nil) { daysAgo in
        [0, 3, 5, 8, 11, 13].contains(daysAgo) ? 75 : nil
    }
}

#Preview("Empty") {
    previewSleepDebtCard { daysAgo in
        daysAgo < 3 ? 40 : nil
    }
}
