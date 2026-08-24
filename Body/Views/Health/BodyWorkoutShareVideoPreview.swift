//
//  BodyWorkoutShareVideoPreview.swift
//  Body
//
//  The moving half of a video-background share preview: an `AVPlayerLayer` the share
//  sheet puts *under* the (transparent-backed) card, inside the same preview-scaled
//  container, so the clip and the overlay can never drift apart. `AVPlayerLayer` is
//  the view's own backing layer rather than a sublayer, so it resizes with the view
//  without a manual `layoutSubviews` pass. `.resizeAspectFill` matches the card's
//  `scaledToFill` photo layer — the sheet's pan/zoom chain then frames it exactly as
//  it frames a photo, and `WorkoutShareVideoComposer` reproduces the same fill on
//  export.
//

import AVFoundation
import SwiftUI
import UIKit

struct BodyWorkoutShareVideoPreview: UIViewRepresentable {
    /// Optional so the sheet can hand over whatever it currently holds — a torn-down
    /// player leaves the layer empty rather than forcing the view out of the hierarchy.
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        // The sheet sizes this view to the clip's aspect-fill size, so a plain resize
        // is already aspect-correct — and, unlike aspect-fill, it can't crop.
        view.playerLayer.videoGravity = .resize
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        var playerLayer: AVPlayerLayer {
            // Safe by construction: `layerClass` above is what backs this view.
            layer as! AVPlayerLayer
        }
    }
}
