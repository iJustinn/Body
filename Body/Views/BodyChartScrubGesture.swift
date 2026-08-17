//
//  BodyChartScrubGesture.swift
//  Body
//

import SwiftUI
import UIKit

/// Hold-to-scrub for a chart that lives inside a `ScrollView`, as a UIKit recognizer
/// so scrolling keeps working: a UIScrollView pan coexists with subview long presses
/// (moving before the hold succeeds scrolls and cancels the press; a stationary hold
/// fires it), whereas a SwiftUI
/// `LongPressGesture.sequenced(before: DragGesture(minimumDistance: 0))` never fails
/// and starves the scroll pan of every touch that starts on the chart.
///
/// `allowableMovement` only bounds the finger *before* recognition, so once `.began`
/// lands the finger can slide freely along the plot and every `.changed` reports its
/// current `location(in:)` — the scrub. Generalized from
/// `BodyActivityRingPeekLongPressGesture`, which peeks a single calendar cell.
struct BodyChartScrubGesture: UIGestureRecognizerRepresentable {
    /// `.gesture(_:isEnabled:)` requires a SwiftUI `Gesture`, which a representable is
    /// not — so an empty chart disables the recognizer itself instead.
    var isEnabled: Bool = true
    /// The touch's position in the attached view while the hold is active, and nil the
    /// moment it ends, cancels or fails.
    let onChange: (CGPoint?) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0.35
        recognizer.allowableMovement = 12
        // The chart is purely visual, but the sheet's buttons and the scroll view
        // around it must keep their touches while the hold is being evaluated.
        recognizer.cancelsTouchesInView = false
        recognizer.isEnabled = isEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChange(recognizer.location(in: recognizer.view))
        case .ended, .cancelled, .failed:
            onChange(nil)
        default:
            break
        }
    }
}
