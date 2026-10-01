//
//  BodyHingeReader.swift
//  Body
//

import SwiftUI
import UIKit

/// The posture of a foldable iPhone's hinge, as `UIHingeInteraction` reports it.
enum BodyHingeStatus {
    case unknown
    case closed
    case partiallyOpen
    case fullyOpen
}

/// The hinge posture Home lays its inner screen out from, fed by `BodyHingeReader`.
@Observable
final class BodyHingeState {
    var status: BodyHingeStatus = .unknown
}

/// A zero-size view carrying the `UIHingeInteraction` (iOS 27.1) that reports the
/// hinge posture into `state`. Before iOS 27.1, or off a foldable, the status stays
/// `.unknown`. The interaction is compiled only against the iOS 27.1 SDK or later
/// (UIKit module 9127.0.85; the 27.0 SDK ships 9127.0.84), so a build from the
/// release Xcode 27.0 leaves the status `.unknown` too.
struct BodyHingeReader: UIViewRepresentable {
    let state: BodyHingeState

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        #if canImport(UIKit, _version: 9127.0.85)
        if #available(iOS 27.1, *) {
            let interaction = UIHingeInteraction { _, update in
                let status: BodyHingeStatus
                switch update.hinge?.status {
                case .closed: status = .closed
                case .partiallyOpen: status = .partiallyOpen
                case .fullyOpen: status = .fullyOpen
                case .unknown, .none: status = .unknown
                @unknown default: status = .unknown
                }
                if state.status != status {
                    state.status = status
                }
            }
            view.addInteraction(interaction)
        }
        #endif
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
