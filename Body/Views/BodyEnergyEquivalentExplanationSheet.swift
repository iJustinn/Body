//
//  BodyEnergyEquivalentExplanationSheet.swift
//  Body
//

import SwiftUI

/// Explains the workout detail page's "Equivalent" card: what the breakdown
/// means and the fixed kcal table behind every food emoji it can show.
///
/// It lives in its own file rather than in `BodyWorkoutsView` because
/// `ProjectConfigurationTests.testAppSheetsShareTheTintedGlassBackdrop` pins that
/// file's shared-sheet-backdrop count at zero — the workout detail page keeps its own
/// tint→black gradient instead. (That guard counts raw source occurrences, so naming
/// the modifier here would itself break it.)
struct BodyEnergyEquivalentExplanationSheet: View {
    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    introCard
                    foodTableCard
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
        String(localized: "About the Equivalent Card")
    }

    private var introCard: some View {
        explanationCard(
            title: Self.sheetTitle,
            // Wording stays source-neutral: the card can be computed from active
            // or total energy depending on the Total Energy setting.
            body: String(localized: "Equivalent turns this workout's burned energy into a handful of food emoji, so a calorie count feels more tangible. Each food stands for a fixed estimate rather than something looked up in a nutrition database, so it is only a playful comparison, not dietary advice.")
        )
    }

    private var foodTableCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The Food Table")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 14) {
                // The zero-kcal ice-cube filler pads sparse breakdowns, so the
                // table explains it alongside the real foods.
                ForEach(EnergyEquivalent.foods + [EnergyEquivalent.iceCube]) { food in
                    HStack(spacing: 12) {
                        Text(food.emoji)
                            .font(.system(size: 26))

                        Text(food.name)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        Spacer(minLength: 8)

                        Text("equivalent.food.kcalFormat \(Int(food.kilocalories))")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(translucent: true)
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
