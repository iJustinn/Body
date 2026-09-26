//
//  BodyRadarWarningCard.swift
//  Body
//

import SwiftUI

/// The Body Radar detail page's warning card, shown while the latest frozen
/// night reads Minor or Major signs (the same night the Home badge flags). It
/// says which night, why the verdict was confirmed, and which signals moved.
struct BodyRadarWarningCard: View {
    let night: BodyRadarNight
    var onDismiss: (() -> Void)? = nil

    private var tint: Color {
        BodyRadarChartStyle.color(for: night.region)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .bold))
                Text(night.state.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                Spacer(minLength: 0)

                if let onDismiss {
                    BodyWarningCardCloseButton(action: onDismiss)
                }
            }
            .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 6) {
                Text(sentence)

                if let corroborationText {
                    Text(corroborationText)
                }
            }
            .font(.system(.subheadline, design: .rounded))
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            signalRows

            Text(String(
                localized: "bodyRadar.warning.footnote",
                defaultValue: "Rest and notice how you feel. Body Radar is not a medical device."
            ))
            .font(.system(.footnote, design: .rounded))
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(translucent: true)
    }

    /// The flagged signals, each with the way it moved. A combination can reach
    /// Minor without any one signal standing out, so that night gets the
    /// calculator's own explanation instead of an empty list.
    @ViewBuilder
    private var signalRows: some View {
        let signals = night.flaggedSignals

        if signals.isEmpty {
            Text(night.unflaggedExplanation)
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(signals) { signal in
                    HStack(spacing: 10) {
                        Image(systemName: signal.kind.symbolName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(tint)
                            .frame(width: 24)
                            .accessibilityHidden(true)

                        Text(signal.kind.title)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Spacer(minLength: 8)

                        HStack(spacing: 4) {
                            Image(systemName: signal.deviation >= 0 ? "arrow.up" : "arrow.down")
                                .foregroundStyle(tint)
                                .accessibilityHidden(true)
                            Text(directionText(for: signal))
                                .foregroundColor(.secondary)
                        }
                        .font(.system(.subheadline, design: .rounded))
                        .fixedSize()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var sentence: String {
        let day = night.date.formatted(.dateTime.month(.abbreviated).day())
        return String(
            localized: "bodyRadar.warning.sentence",
            defaultValue: "Your overnight readings for \(day) moved away from your personal range."
        )
    }

    private var corroborationText: String? {
        switch night.corroboration {
        case .sameNight:
            return String(
                localized: "bodyRadar.warning.sameNight",
                defaultValue: "More than one kind of change showed up on the same night."
            )
        case .persistence:
            return String(
                localized: "bodyRadar.warning.persistence",
                defaultValue: "The change continued from the night before."
            )
        case .some(.none), nil:
            return nil
        }
    }

    private func directionText(for signal: BodyRadarSignal) -> String {
        signal.deviation >= 0
            ? String(localized: "bodyRadar.warning.higher", defaultValue: "Higher")
            : String(localized: "bodyRadar.warning.lower", defaultValue: "Lower")
    }
}
