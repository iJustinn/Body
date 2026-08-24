//
//  BodyReadinessImpactExplanationSheet.swift
//  Body
//

import SwiftUI

/// Explains the Readiness detail page's "Impact by Activity" card: what each row is,
/// and — the reason the sheet exists — why the listed drops can add up to more than the
/// readiness the day started with (`ActivityReadinessImpact.displayedScore(forRawScore:)`
/// eases the score down instead of letting it fall one for one near the floor).
///
/// The copy stays behavioural on purpose: it describes what the user sees, never the
/// weights, caps, or step sizes behind it.
///
/// It lives in its own file rather than in `BodyHealthMetricDetailView` because
/// `ProjectConfigurationTests.testAppSheetsShareTheTintedGlassBackdrop` pins the shared
/// backdrop per file, and the metric detail file carries no count of its own.
struct BodyReadinessImpactExplanationSheet: View {
    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    introCard
                    softFloorCard
                    measurementCard
                    dailyCapCard
                    todayOnlyCard
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
        String(localized: "About Impact by Activity")
    }

    private var introCard: some View {
        explanationCard(
            title: Self.sheetTitle,
            body: String(localized: "This card lists every workout that moved the day's readiness, in the order the sessions finished, with the share of the drop each one accounts for. A session too light to move the score is left out, and a day without workouts shows none at all.")
        )
    }

    private var softFloorCard: some View {
        explanationCard(
            title: String(localized: "Why the Total Can Exceed Your Score"),
            body: String(localized: "Readiness does not keep falling one for one once it nears the bottom of the scale. Below roughly 5% it eases down far more slowly, so even a very hard day settles just above zero rather than dropping straight to it. That is why the impacts listed here can add up to more than the readiness you started the day with, and why the chart above falls by less than those numbers together suggest.")
        )
    }

    private var measurementCard: some View {
        explanationCard(
            title: String(localized: "What Shapes Each Impact"),
            body: String(localized: "A session counts for more when it runs longer, when you worked harder, and when the activity is more demanding on the body as a whole, so an easy walk barely registers beside a hard run of the same length. Effort comes from the rating you saved for the session, and when there is none Body estimates it from your average heart rate and energy burn. Very long sessions level off rather than draining without limit.")
        )
    }

    private var dailyCapCard: some View {
        explanationCard(
            title: String(localized: "The Daily Ceiling"),
            body: String(localized: "However much you train, there is a limit to how far one day's workouts can pull your readiness down. Each row shows only what its own session actually moved the score, so once earlier workouts have taken the day close to that limit, a later one is credited with just the remainder and can read much smaller than the same session would on a fresh day.")
        )
    }

    private var todayOnlyCard: some View {
        explanationCard(
            title: String(localized: "It Only Applies to Today"),
            body: String(localized: "This drop is a layer on top of today's live score. It builds up across the day, does not fade back on its own, and clears with the next morning's score. It never rewrites history: the Week, Month, and longer trend charts keep the score you woke up with, while the Day View chart above replays how the day's workouts brought it down.")
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
