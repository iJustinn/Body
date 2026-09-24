//
//  BodyBasicsRangeExplanationSheet.swift
//  Body
//

import SwiftUI

/// Explains the Basics detail page's "Difference Range" card: what the ± tiles
/// measure and how the PM vs AM weight difference is worked out.
///
/// It lives in its own file rather than in `BodyHealthMetricDetailView` because
/// `ProjectConfigurationTests.testAppSheetsShareTheTintedGlassBackdrop` pins the shared
/// backdrop per file, and the metric detail file carries no count of its own.
struct BodyBasicsRangeExplanationSheet: View {
    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    introCard
                    rangeCard
                    afternoonMorningCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
            .bodySheetBackground()
            .navigationTitle(Self.sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Shared by the sheet's title and the card header's button label, so the two can
    /// never drift and the catalog carries one key instead of two case-only variants.
    static var sheetTitle: String {
        String(localized: "About Difference Range")
    }

    private var introCard: some View {
        explanationCard(
            title: Self.sheetTitle,
            body: String(localized: "This card shows how much your body fat, weight, and BMI moved over the range selected above, Week, Month, 6 Months, or Year. It follows the selector, so switching the range recalculates every tile. A tile reads as two dashes when the range holds no data for it.")
        )
    }

    private var rangeCard: some View {
        explanationCard(
            title: String(localized: "The ± Values"),
            body: String(localized: "Each ± value is half the distance between the lowest and the highest daily value in the range. A weight of ±1.2 means your daily weights stayed within about 1.2 above or below the middle of that span. The daily value is the average of that day's measurements, so one odd reading among several moves it less. Normal swings from water, food, and the time you step on the scale are part of this number, so a small value points to a steady period rather than to no change at all.")
        )
    }

    private var afternoonMorningCard: some View {
        explanationCard(
            title: String(localized: "PM vs AM"),
            body: String(localized: "The average of every weight measured from noon onward, minus the average of every weight measured before noon, across the selected range. A plus means you weigh more later in the day, which is usual after meals and drinks. It needs at least one measurement on each side of noon, and it compares the two groups as a whole rather than day by day, so if your weight is trending and you weigh in at different times on different days, part of the trend shows up here. The Time of Day card below shows when your measurements were taken.")
        )
    }

    private func explanationCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text(body)
                .font(.system(.body, design: .rounded))
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(translucent: true)
    }
}
