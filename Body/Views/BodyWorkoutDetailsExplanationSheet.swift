//
//  BodyWorkoutDetailsExplanationSheet.swift
//  Body
//

import SwiftUI

/// Explains the workout detail page's "Details" card: what the card is, what the
/// 30-day comparison badges mean, and what each tile measures.
///
/// It lives in its own file rather than in `BodyWorkoutsView` because
/// `ProjectConfigurationTests.testAppSheetsShareTheTintedGlassBackdrop` pins that
/// file's shared-sheet-backdrop count at zero — the workout detail page keeps its own
/// tint→black gradient instead. (That guard counts raw source occurrences, so naming
/// the modifier here would itself break it.)
///
/// The rows are driven by the tiles the card is actually showing, so a swim never
/// carries cycling-cadence copy. Headings reuse each tile's own `title`, which is
/// already localized and already unit-correct ("Active kcal" vs "Active kJ"), so the
/// sheet can never disagree with the grid behind it.
struct BodyWorkoutDetailsExplanationSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// The card's resolved tiles, in the order the grid draws them.
    let metrics: [WorkoutDetailMetric]
    /// Whether the card is showing comparison badges at all; when it isn't, the
    /// paragraph explaining them would describe something the user cannot see.
    let showsComparison: Bool

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    introCard

                    if showsComparison {
                        comparisonCard
                    }

                    ForEach(metrics, id: \.kind) { metric in
                        explanationCard(
                            title: metric.title,
                            body: Self.explanation(for: metric.kind)
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
            .bodySheetBackground()
            .navigationTitle(Self.sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                }
            }
        }
    }

    /// Shared by the sheet's title and the card header's button label, so the two can
    /// never drift and the catalog carries one key instead of two case-only variants.
    static var sheetTitle: String {
        String(localized: "About These Details")
    }

    private var introCard: some View {
        explanationCard(
            title: Self.sheetTitle,
            body: String(localized: "These tiles summarize what Apple Health recorded for this workout. Which tiles appear depends on the workout type and on the device that recorded the session, so a workout without heart-rate or GPS data simply shows fewer of them. Most values come straight from Apple Health, and a few, such as pace, speed, and cadence, are worked out by Body from the distance, duration, and counts Apple Health stored.")
        )
    }

    private var comparisonCard: some View {
        explanationCard(
            title: String(localized: "The Comparison Badges"),
            body: String(localized: "The small badge above a tile's unit compares that value against your average for the same workout type over the 30 days before this session. It shows direction only, with no judgment about whether higher is better: an up arrow means this workout was above that average, a down arrow means below, and a value near zero means you were on par. While the history is still loading the badge holds a 0% stand-in and the label beside Details reads Calculating, then the digits roll into the real percentage. Once loading has settled without enough comparable history the badge reads --%, because a zero there would wrongly claim the metric matched your average. Some tiles carry no badge at all, either because the metric has no comparable value or because it arrived after the comparison was built.")
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

    /// One explanation per tile kind. Keyed on `Kind` rather than on the tile's title
    /// because `.pace` and `.swimPace` share the title "Avg Pace" but measure different
    /// things (per km/mi vs per 100 m/yd).
    static func explanation(for kind: WorkoutDetailMetric.Kind) -> String {
        switch kind {
        case .distance:
            return String(localized: "How far you traveled during the session, from GPS where it was available and from motion sensors otherwise. Indoor workouts fall back to motion, so a treadmill distance can differ from the machine's own readout.")
        case .pace:
            return String(localized: "Your average time to cover one kilometer or one mile, following your distance unit setting. It is worked out from the total distance and the full elapsed time, so warm-up, slow sections, and any rests are all counted in.")
        case .speed:
            return String(localized: "Your average distance covered per hour, worked out from the total distance and the full elapsed time. Stops at traffic lights and rest periods are included, so this usually reads lower than the speed you held while actually moving.")
        case .swimPace:
            return String(localized: "Your average time to swim 100 meters or 100 yards, following your distance unit setting. It is based on the total distance and the full elapsed time, so rest between sets is counted in.")
        case .elevation:
            return String(localized: "The total climbing you did, adding up every uphill section rather than measuring the difference between your start and finish. A barometric altimeter measures this more accurately than GPS alone.")
        case .activeEnergy:
            return String(localized: "The energy your body used through movement during this session, above what it would have burned at rest. This is the number Apple Health credits toward your Move ring.")
        case .totalEnergy:
            return String(localized: "Active energy plus the resting energy your body would have used anyway over the same period. When the session recorded no resting energy, this falls back to the active number alone, so the two tiles can read exactly the same.")
        case .avgHeartRate:
            return String(localized: "Your average beats per minute across the session. Warm-up and cool-down are included, so it usually sits below the effort you felt at your hardest.")
        case .maxHeartRate:
            return String(localized: "The highest single beats-per-minute reading recorded during the session. A loose watch band or cold skin can produce a brief spike that does not reflect real effort.")
        case .stepCadence:
            return String(localized: "How many steps you took per minute, counting both feet. At a given pace, a higher cadence usually means shorter strides and less impact through each one.")
        case .cyclingCadence:
            return String(localized: "How many pedal revolutions you turned per minute. It needs a device or paired sensor that records cadence, so it will not appear on every ride.")
        case .power:
            return String(localized: "Your average mechanical output in watts, which is how much work you actually did rather than how hard it felt. Unlike heart rate it responds instantly and is not pushed around by heat, caffeine, or fatigue.")
        case .cardioFitness:
            return String(localized: "An estimate of your VO₂ max, the maximum amount of oxygen your body can use during exercise. Apple Watch records one only after an outdoor walk, run, or hike on fairly flat ground with a good GPS and heart-rate signal, which is why most workouts show no value here.")
        case .strokeCount:
            return String(localized: "The total number of swim strokes counted across the session, added up over every length you swam.")
        case .humidity:
            return String(localized: "How much moisture was in the air where you worked out. High humidity makes it harder for your body to shed heat, which can raise your heart rate at a pace that normally feels easy.")
        case .averageMETs:
            return String(localized: "Metabolic equivalents, a measure of intensity where 1 MET is roughly the energy you use sitting still. An average of 8 METs means the session took about eight times that.")
        case .heartRateRecovery:
            return String(localized: "How far your heart rate fell during the first minute after you stopped. A larger drop generally points to better cardiovascular fitness, and your own usual range tells you more than any single reading.")
        }
    }
}
