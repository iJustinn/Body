//
//  WorkoutShareVideo.swift
//  Body
//
//  The video half of the workout share card's background. A picked clip is copied into
//  a per-clip scratch directory (`tmp/WorkoutShareVideo/<id>/`), inspected once into a
//  `WorkoutShareVideoClip`, previewed by an `AVPlayer`, and exported by
//  `WorkoutShareVideoComposer` as an MP4 with the card rendered once and held over every
//  frame. Everything here is session-only: nothing is persisted, and the whole directory
//  is removed when the clip is replaced or the sheet goes away.
//
//  Only the first `WorkoutShareVideoComposer.maximumDuration` (60 s) is ever exported —
//  there is no trim UI — and the export is always 30 fps SDR BT.709 at the card's pixel
//  size, so slow-motion and HDR sources come out as ordinary shareable video.
//

import AVFoundation
import CoreImage
import CoreMedia
import CoreTransferable
import Foundation
import UIKit
import UniformTypeIdentifiers

/// What can go wrong between picking a clip and having an MP4.
enum WorkoutShareVideoError: Error {
    /// The picked file has no video track (an audio-only file, or something unreadable).
    case noVideoTrack
    /// The duration is non-numeric (a live stream) or zero — nothing to export.
    case unusableDuration
    /// `AVAssetExportSession` refused to initialize for the composition.
    case exportSessionUnavailable
    /// The export itself failed; carries AVFoundation's error.
    case exportFailed(Error)
}

/// A clip the user picked, inspected once so the preview and the export can share the
/// same `AVURLAsset` (loading it twice would re-read the file for no reason).
///
/// Session-only, never stored. `id` names the scratch directory that holds both our copy
/// of the source file and any exports made from it, so tearing the clip down is a single
/// directory removal.
struct WorkoutShareVideoClip: Equatable {
    /// Names the scratch directory: `tmp/WorkoutShareVideo/<id>/`.
    let id: UUID
    /// The inspected asset — reused by the preview player, so it is already loaded.
    let asset: AVURLAsset
    /// Our own copy of the picked file: `tmp/WorkoutShareVideo/<id>/source.<ext>`.
    let url: URL
    /// The video track's stored pixel size, before `preferredTransform`.
    let naturalSize: CGSize
    /// The track's orientation transform (portrait phone clips are stored landscape).
    let preferredTransform: CGAffineTransform
    /// `naturalSize` after `preferredTransform`, absolute — what the viewer actually sees,
    /// and what the pan/zoom clamp treats as the "image size".
    let orientedSize: CGSize
    /// Numeric and greater than zero; `load` throws `.unusableDuration` otherwise.
    let duration: CMTime
    let hasAudio: Bool
    /// A small upright still from t = 0, used as the picker tile's thumbnail.
    let poster: UIImage
    /// `0 … min(duration, 60 s)` — the only range the preview loops and the export writes.
    var exportTimeRange: CMTimeRange

    /// Two clips are the same clip when they came from the same scratch copy; `poster`
    /// and the loaded asset are derived state and would only make equality expensive.
    static func == (lhs: WorkoutShareVideoClip, rhs: WorkoutShareVideoClip) -> Bool {
        lhs.id == rhs.id && lhs.url == rhs.url
    }

    /// Reads the tracks, duration and poster of an already-local file.
    ///
    /// - Throws: `.noVideoTrack` when there is no video track at all, `.unusableDuration`
    ///   when the duration is non-numeric or not positive.
    static func load(url: URL) async throws -> WorkoutShareVideoClip {
        let asset = AVURLAsset(url: url)
        let (tracks, duration) = try await asset.load(.tracks, .duration)

        guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
            throw WorkoutShareVideoError.noVideoTrack
        }
        guard duration.isNumeric, duration.seconds > 0 else {
            throw WorkoutShareVideoError.unusableDuration
        }

        let (naturalSize, preferredTransform) = try await videoTrack.load(
            .naturalSize, .preferredTransform
        )
        let orientedRect = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
        let orientedSize = CGSize(
            width: abs(orientedRect.width),
            height: abs(orientedRect.height)
        )

        // The clip's identity is the scratch directory `VideoFileTransfer` copied into —
        // minting a fresh one here would point `scratchDirectory()` at an empty directory
        // and leak the full-size source copy for the rest of the session. The fallback is
        // only for a file that does not live in a scratch directory (tests, fixtures).
        let id = UUID(uuidString: url.deletingLastPathComponent().lastPathComponent) ?? UUID()

        return WorkoutShareVideoClip(
            id: id,
            asset: asset,
            url: url,
            naturalSize: naturalSize,
            preferredTransform: preferredTransform,
            orientedSize: orientedSize,
            duration: duration,
            hasAudio: tracks.contains { $0.mediaType == .audio },
            poster: await makePoster(asset: asset),
            exportTimeRange: WorkoutShareVideoComposer.exportTimeRange(forDuration: duration)
        )
    }

    /// The clip's own scratch directory. Named by `id`, so removing it takes the source
    /// copy and every export made from it at once.
    func scratchDirectory() -> URL {
        Self.scratchDirectory(for: id)
    }

    static func scratchDirectory(for id: UUID) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("WorkoutShareVideo", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Creates `tmp/WorkoutShareVideo/<id>/`, including intermediates.
    @discardableResult
    static func makeScratchDirectory(for id: UUID) throws -> URL {
        let directory = scratchDirectory(for: id)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        return directory
    }

    /// Best-effort teardown — a clip that was never written leaves nothing to remove.
    static func removeScratch(for id: UUID) {
        try? FileManager.default.removeItem(at: scratchDirectory(for: id))
    }

    /// An upright still from t = 0, capped at 600 px. A generator failure is not worth
    /// failing the whole pick over, so an empty image stands in.
    private static func makePoster(asset: AVURLAsset) async -> UIImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        if let (image, _) = try? await generator.image(at: .zero) {
            return UIImage(cgImage: image)
        }
        return UIImage()
    }
}

/// How a `PhotosPickerItem` movie arrives. The picker hands us a temporary file that goes
/// away as soon as the transfer closure returns (and may be an iCloud download), so the
/// import copies it into a fresh scratch directory we own for the rest of the session.
struct VideoFileTransfer: Transferable {
    let url: URL
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { transfer in
            SentTransferredFile(transfer.url)
        } importing: { received in
            let id = UUID()
            let directory = try WorkoutShareVideoClip.makeScratchDirectory(for: id)
            let fileExtension = received.file.pathExtension.isEmpty
                ? "mov"
                : received.file.pathExtension
            let destination = directory.appendingPathComponent("source")
                .appendingPathExtension(fileExtension)
            do {
                try FileManager.default.copyItem(at: received.file, to: destination)
            } catch {
                WorkoutShareVideoClip.removeScratch(for: id)
                throw error
            }
            return VideoFileTransfer(url: destination, id: id)
        }
    }
}

/// Builds the exported MP4: the clip's first 60 s, filled into the card's pixel rect with
/// the user's pan/zoom, with the once-rendered card overlaid on every frame.
enum WorkoutShareVideoComposer {
    /// The hard cut — there is no trim UI, so a longer clip simply loses its tail.
    static let maximumDuration = CMTime(seconds: 60, preferredTimescale: 600)
    /// The card renders at 3×, the same scale `ImageRenderer` uses for the still export.
    static let renderScale: CGFloat = 3
    /// Fixed 30 fps: slow-mo/120 fps sources are resampled, never exported at source cadence.
    static let frameDuration = CMTime(value: 1, timescale: 30)

    /// `0 … min(duration, maximumDuration)` — pure, so it can be unit-tested without a
    /// media file. `load(url:)` calls this to seed a fresh clip's `exportTimeRange`.
    static func exportTimeRange(forDuration duration: CMTime) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: min(duration, maximumDuration))
    }

    /// The pixel-space source → render transform, in this order:
    /// 1. `preferredTransform`, then a translation by −origin of the transformed natural
    ///    rect so the upright frame sits at (0, 0) with size `orientedSize`;
    /// 2. `scaledToFill`: `s = max(renderW / orientedW, renderH / orientedH)`, centred;
    /// 3. zoom by `photoTransform.scale` about the render centre;
    /// 4. translate by `photoTransform.offset × renderScale`.
    ///
    /// Pure — the preview applies the same chain in points, this one works in pixels.
    static func fillTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        cardSize: CGSize,
        photoTransform: WorkoutSharePhotoTransform
    ) -> CGAffineTransform {
        let orientedRect = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
        let orientedWidth = abs(orientedRect.width)
        let orientedHeight = abs(orientedRect.height)
        let renderSize = renderSize(for: cardSize)

        guard orientedWidth > 0, orientedHeight > 0,
              renderSize.width > 0, renderSize.height > 0 else {
            return preferredTransform
        }

        // (1) upright at the origin
        var transform = preferredTransform.concatenating(
            CGAffineTransform(translationX: -orientedRect.minX, y: -orientedRect.minY)
        )

        // (2) scaledToFill, centred
        let fill = max(renderSize.width / orientedWidth, renderSize.height / orientedHeight)
        transform = transform.concatenating(CGAffineTransform(scaleX: fill, y: fill))
        transform = transform.concatenating(
            CGAffineTransform(
                translationX: (renderSize.width - orientedWidth * fill) / 2,
                y: (renderSize.height - orientedHeight * fill) / 2
            )
        )

        // (3) the user's zoom, about the render centre
        let zoom = photoTransform.scale
        if zoom != 1 {
            let centreX = renderSize.width / 2
            let centreY = renderSize.height / 2
            transform = transform
                .concatenating(CGAffineTransform(translationX: -centreX, y: -centreY))
                .concatenating(CGAffineTransform(scaleX: zoom, y: zoom))
                .concatenating(CGAffineTransform(translationX: centreX, y: centreY))
        }

        // (4) the user's pan, in card points scaled to pixels
        transform = transform.concatenating(
            CGAffineTransform(
                translationX: photoTransform.offset.width * renderScale,
                y: photoTransform.offset.height * renderScale
            )
        )

        return transform
    }

    /// The exported pixel size for a card measured in points.
    static func renderSize(for cardSize: CGSize) -> CGSize {
        CGSize(width: cardSize.width * renderScale, height: cardSize.height * renderScale)
    }

    /// The upright clip scaled to fill `cardSize` (step 2 of `fillTransform`, in points):
    /// one axis equals the card, the other overhangs. The preview sizes its player layer
    /// to this — an `AVPlayerLayer` clips to its own bounds, so a card-sized layer would
    /// throw the overhang away before the pan could use it, and the preview would no
    /// longer rehearse the export.
    static func fillSize(orientedSize: CGSize, in cardSize: CGSize) -> CGSize {
        guard orientedSize.width > 0, orientedSize.height > 0 else { return cardSize }
        let scale = max(cardSize.width / orientedSize.width, cardSize.height / orientedSize.height)
        return CGSize(width: orientedSize.width * scale, height: orientedSize.height * scale)
    }

    /// `fillTransform` is stated in video's top-left-origin pixel space; Core Image works
    /// bottom-left-origin, so it is sandwiched between a flip of the source height and a
    /// flip of the render height.
    static func coreImageTransform(
        _ transform: CGAffineTransform, sourceHeight: CGFloat, renderHeight: CGFloat
    ) -> CGAffineTransform {
        CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: sourceHeight)
            .concatenating(transform)
            .concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: renderHeight))
    }

    /// Composes and exports. Writes to `<clip scratch>/export-<uuid>.mp4` and returns it.
    ///
    /// Cancellation propagates as `CancellationError` (the sheet cancels the owning task
    /// when the user leaves); everything else is wrapped in `.exportFailed`.
    static func export(
        clip: WorkoutShareVideoClip,
        overlay: UIImage,
        cardSize: CGSize,
        photoTransform: WorkoutSharePhotoTransform
    ) async throws -> URL {
        let renderSize = renderSize(for: cardSize)
        let composition = AVMutableComposition()

        guard let sourceVideoTrack = try await clip.asset.loadTracks(withMediaType: .video).first,
              let videoTrack = composition.addMutableTrack(
                  withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw WorkoutShareVideoError.noVideoTrack
        }
        try videoTrack.insertTimeRange(clip.exportTimeRange, of: sourceVideoTrack, at: .zero)

        // Audio only where the source actually has some: a track shorter than (or starting
        // later than) the video leaves silence at the right place instead of shifting.
        if let sourceAudioTrack = try await clip.asset.loadTracks(withMediaType: .audio).first {
            let audioRange = try await sourceAudioTrack.load(.timeRange)
            let usable = audioRange.intersection(clip.exportTimeRange)
            if usable.duration.isNumeric, usable.duration.seconds > 0,
               let audioTrack = composition.addMutableTrack(
                   withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                try audioTrack.insertTimeRange(usable, of: sourceAudioTrack, at: usable.start)
            }
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = frameDuration
        videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        videoComposition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        videoComposition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

        videoComposition.customVideoCompositorClass = WorkoutShareVideoCompositor.self

        let fill = fillTransform(
            naturalSize: clip.naturalSize,
            preferredTransform: clip.preferredTransform,
            cardSize: cardSize,
            photoTransform: photoTransform
        )
        videoComposition.instructions = [
            WorkoutShareVideoOverlayInstruction(
                timeRange: CMTimeRange(start: .zero, duration: composition.duration),
                trackID: videoTrack.trackID,
                transform: coreImageTransform(
                    fill, sourceHeight: clip.naturalSize.height, renderHeight: renderSize.height
                ),
                overlay: overlay.cgImage.map { CIImage(cgImage: $0) },
                renderSize: renderSize
            )
        ]

        guard let session = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw WorkoutShareVideoError.exportSessionUnavailable
        }
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true

        let directory = try WorkoutShareVideoClip.makeScratchDirectory(for: clip.id)
        let outputURL = directory
            .appendingPathComponent("export-\(UUID().uuidString)")
            .appendingPathExtension("mp4")

        do {
            try await session.export(to: outputURL, as: .mp4)
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            if Task.isCancelled { throw CancellationError() }
            throw WorkoutShareVideoError.exportFailed(error)
        }

        return outputURL
    }
}

/// One instruction for the whole export: the card overlay never changes and the pan/zoom
/// is fixed at the moment Share is tapped, so there is nothing to tween.
/// `@unchecked Sendable`: the protocol requires Sendable, and every stored property is
/// a `let` set once in `init` — the NSValue/CIImage members are never mutated after.
final class WorkoutShareVideoOverlayInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = false
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid

    let trackID: CMPersistentTrackID
    /// Source → render, already converted to Core Image's bottom-left-origin space.
    let transform: CGAffineTransform
    /// The card, rendered once at render size; nil only if the overlay had no bitmap.
    let overlay: CIImage?
    let renderSize: CGSize

    init(
        timeRange: CMTimeRange,
        trackID: CMPersistentTrackID,
        transform: CGAffineTransform,
        overlay: CIImage?,
        renderSize: CGSize
    ) {
        self.timeRange = timeRange
        self.trackID = trackID
        self.transform = transform
        self.overlay = overlay
        self.renderSize = renderSize
        self.requiredSourceTrackIDs = [NSNumber(value: trackID)]
        super.init()
    }
}

/// Draws each frame with Core Image: the source scaled to fill the card, the card overlay
/// on top, on black.
///
/// This replaces `AVVideoCompositionCoreAnimationTool`, which renders through a
/// `CARenderer` that traps (`IOSurfaceCreate` → `_xpc_api_misuse`) inside the iOS
/// Simulator at any render size — that would leave the entire export path untestable.
/// Core Image runs identically on both, and gives the overlay's orientation explicitly
/// rather than through the layer tree's origin convention.
final class WorkoutShareVideoCompositor: NSObject, AVVideoCompositing {
    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA]
    ]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA]
    ]

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private var renderContext: AVVideoCompositionRenderContext?

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContext = newRenderContext
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let renderContext,
              let instruction = request.videoCompositionInstruction
                as? WorkoutShareVideoOverlayInstruction,
              let source = request.sourceFrame(byTrackID: instruction.trackID),
              let destination = renderContext.newPixelBuffer() else {
            request.finish(
                with: WorkoutShareVideoError.exportSessionUnavailable
            )
            return
        }

        let rect = CGRect(origin: .zero, size: instruction.renderSize)
        var image = CIImage(cvPixelBuffer: source).transformed(by: instruction.transform)
        if let overlay = instruction.overlay {
            image = overlay.composited(over: image)
        }
        image = image.composited(over: CIImage(color: .black).cropped(to: rect))

        context.render(
            image, to: destination, bounds: rect, colorSpace: colorSpace
        )
        request.finish(withComposedVideoFrame: destination)
    }

    func cancelAllPendingVideoCompositionRequests() {}
}
