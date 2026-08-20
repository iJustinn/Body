//
//  WorkoutShareVideoTests.swift
//  BodyTests
//
//  Covers the video background model: the pure source→render transform (by corner
//  mapping, not coefficients), `WorkoutShareVideoClip.load`'s rejections, the Pro gate,
//  and a full `AVAssetWriter` → `WorkoutShareVideoComposer.export` round trip that pins
//  output size, duration, audio, colour, codec and — via four distinct overlay corner
//  colours — the orientation of the composited overlay.
//
//  Device-only behaviours (iCloud delivery, HDR tone-mapping, a real Photos save) are
//  TestPlan cases, not claimed here.
//

import AVFoundation
import CoreMedia
import XCTest
import UIKit
@testable import Body

final class WorkoutShareVideoTests: XCTestCase {

    // MARK: - fillTransform

    /// Every combination of a source orientation and a card ratio: with no user pan/zoom
    /// the upright source must cover the render rect exactly on one axis, overhang
    /// symmetrically on the other, and stay centred.
    /// The preview's player layer is sized to this, so the aspect-fill overhang is real
    /// layer area the pan can reveal — the same overhang `fillTransform` gives the export.
    func testFillSizeMatchesTheCardOnOneAxisAndOverhangsOnTheOther() {
        let card = CGSize(width: 360, height: 640)
        let landscape = WorkoutShareVideoComposer.fillSize(orientedSize: CGSize(width: 1920, height: 1080), in: card)
        XCTAssertEqual(landscape.height, 640, accuracy: 1e-9)
        XCTAssertEqual(landscape.width, 640 * 1920 / 1080, accuracy: 1e-9)

        let portrait = WorkoutShareVideoComposer.fillSize(orientedSize: CGSize(width: 1080, height: 1920), in: card)
        XCTAssertEqual(portrait.width, 360, accuracy: 1e-9)
        XCTAssertEqual(portrait.height, 640, accuracy: 1e-9)

        let square = WorkoutShareVideoComposer.fillSize(orientedSize: CGSize(width: 720, height: 720), in: card)
        XCTAssertEqual(square.width, 640, accuracy: 1e-9)
        XCTAssertEqual(square.height, 640, accuracy: 1e-9)

        // A degenerate size can't fill anything; the card itself is the safe answer.
        XCTAssertEqual(WorkoutShareVideoComposer.fillSize(orientedSize: .zero, in: card), card)
    }

    func testFillTransformIdentityCoversRenderRectAndStaysCentred() {
        for source in Self.sources {
            for ratio in [WorkoutShareAspectRatio.portrait9x16, .landscape16x9] {
                let render = WorkoutShareVideoComposer.renderSize(for: ratio.cardSize)
                let mapped = Self.mappedRect(source, ratio.cardSize, .identity)
                let label = "\(source.name) on \(ratio.rawValue)"

                XCTAssertLessThanOrEqual(mapped.minX, 0.01, "covers left: \(label)")
                XCTAssertLessThanOrEqual(mapped.minY, 0.01, "covers top: \(label)")
                XCTAssertGreaterThanOrEqual(
                    mapped.maxX, render.width - 0.01, "covers right: \(label)"
                )
                XCTAssertGreaterThanOrEqual(
                    mapped.maxY, render.height - 0.01, "covers bottom: \(label)"
                )

                XCTAssertEqual(mapped.midX, render.width / 2, accuracy: 0.01, "centred x: \(label)")
                XCTAssertEqual(mapped.midY, render.height / 2, accuracy: 0.01, "centred y: \(label)")

                let snugX = abs(mapped.width - render.width) < 0.01
                let snugY = abs(mapped.height - render.height) < 0.01
                XCTAssertTrue(snugX || snugY, "exactly one axis fits: \(label)")
            }
        }
    }

    /// Zooming grows the mapped rect about the render centre — nothing else moves.
    func testFillTransformScaleGrowsAboutRenderCentre() {
        let zoom = WorkoutSharePhotoTransform(offset: .zero, scale: 1.5)
        for source in Self.sources {
            for ratio in [WorkoutShareAspectRatio.portrait9x16, .landscape16x9] {
                let render = WorkoutShareVideoComposer.renderSize(for: ratio.cardSize)
                let base = Self.mappedRect(source, ratio.cardSize, .identity)
                let zoomed = Self.mappedRect(source, ratio.cardSize, zoom)
                let label = "\(source.name) on \(ratio.rawValue)"

                XCTAssertEqual(zoomed.width, base.width * 1.5, accuracy: 0.05, "width: \(label)")
                XCTAssertEqual(zoomed.height, base.height * 1.5, accuracy: 0.05, "height: \(label)")
                XCTAssertEqual(zoomed.midX, render.width / 2, accuracy: 0.01, "centre x: \(label)")
                XCTAssertEqual(zoomed.midY, render.height / 2, accuracy: 0.01, "centre y: \(label)")
            }
        }
    }

    /// A pan is stated in card points and lands in pixels: × `renderScale` (3).
    func testFillTransformOffsetShiftsByRenderScale() {
        let panned = WorkoutSharePhotoTransform(offset: CGSize(width: 10, height: -20), scale: 1)
        for source in Self.sources {
            for ratio in [WorkoutShareAspectRatio.portrait9x16, .landscape16x9] {
                let base = Self.mappedRect(source, ratio.cardSize, .identity)
                let moved = Self.mappedRect(source, ratio.cardSize, panned)
                let label = "\(source.name) on \(ratio.rawValue)"

                XCTAssertEqual(moved.minX, base.minX + 30, accuracy: 0.01, "dx: \(label)")
                XCTAssertEqual(moved.minY, base.minY - 60, accuracy: 0.01, "dy: \(label)")
                XCTAssertEqual(moved.width, base.width, accuracy: 0.01, "width: \(label)")
                XCTAssertEqual(moved.height, base.height, accuracy: 0.01, "height: \(label)")
            }
        }
    }

    // MARK: - load

    func testLoadRejectsFileWithoutVideoTrack() async throws {
        let url = try await Self.makeAudioOnlyFixture(seconds: 1, in: makeScratch())
        do {
            _ = try await WorkoutShareVideoClip.load(url: url)
            XCTFail("expected .noVideoTrack")
        } catch WorkoutShareVideoError.noVideoTrack {
            // expected
        }
    }

    func testLoadRejectsZeroDuration() async throws {
        let url = try await Self.makeZeroDurationFixture(in: makeScratch())
        do {
            _ = try await WorkoutShareVideoClip.load(url: url)
            XCTFail("expected .unusableDuration")
        } catch WorkoutShareVideoError.unusableDuration {
            // expected
        }
    }

    /// Pure — no media file needed. A clip longer than the 60 s cap only ever offers the
    /// first 60 s; `load(url:)` seeds `exportTimeRange` from this same function.
    func testExportTimeRangeClampsNinetySecondsToSixty() {
        let range = WorkoutShareVideoComposer.exportTimeRange(
            forDuration: CMTime(seconds: 90, preferredTimescale: 600)
        )
        XCTAssertEqual(range.start, .zero)
        XCTAssertEqual(range.duration.seconds, 60, accuracy: 0.01)
    }

    /// A clip under the cap gets the whole thing back, not a truncated range.
    func testExportTimeRangeLeavesAClipUnderTheCapWhole() {
        let range = WorkoutShareVideoComposer.exportTimeRange(
            forDuration: CMTime(seconds: 20, preferredTimescale: 600)
        )
        XCTAssertEqual(range.start, .zero)
        XCTAssertEqual(range.duration.seconds, 20, accuracy: 0.01)
    }

    /// `load` wires a real fixture's duration through the same pure function above: a
    /// 20 s clip (under the 60 s cap) keeps its `exportTimeRange` whole rather than
    /// clamping it.
    func testLoadKeepsAnUnderCapClipsExportTimeRangeWhole() async throws {
        let url = try await Self.makeVideoFixture(
            seconds: 20, audioSeconds: nil, in: makeScratch()
        )
        let clip = try await WorkoutShareVideoClip.load(url: url)
        defer { WorkoutShareVideoClip.removeScratch(for: clip.id) }

        XCTAssertEqual(clip.duration.seconds, 20, accuracy: 0.2)
        XCTAssertEqual(clip.exportTimeRange.start, .zero)
        XCTAssertEqual(clip.exportTimeRange.duration.seconds, 20, accuracy: 0.2)
        XCTAssertEqual(clip.orientedSize, CGSize(width: 640, height: 480))
        XCTAssertFalse(clip.hasAudio)
    }

    /// The clip's identity is the scratch directory it was copied into — otherwise the
    /// source copy is orphaned and the export lands somewhere else entirely.
    func testLoadAdoptsScratchDirectoryIdentity() async throws {
        let id = UUID()
        let directory = try WorkoutShareVideoClip.makeScratchDirectory(for: id)
        addTeardownBlock { WorkoutShareVideoClip.removeScratch(for: id) }

        let fixture = try await Self.makeVideoFixture(
            seconds: 1, audioSeconds: nil, in: makeScratch()
        )
        let source = directory.appendingPathComponent("source.mp4")
        try FileManager.default.copyItem(at: fixture, to: source)

        let clip = try await WorkoutShareVideoClip.load(url: source)
        XCTAssertEqual(clip.id, id)
        XCTAssertEqual(clip.scratchDirectory().standardizedFileURL, directory.standardizedFileURL)

        WorkoutShareVideoClip.removeScratch(for: clip.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    // MARK: - Pro gate

    func testResolvedVideoRequiresPro() async throws {
        let url = try await Self.makeVideoFixture(
            seconds: 1, audioSeconds: nil, in: makeScratch()
        )
        let clip = try await WorkoutShareVideoClip.load(url: url)
        defer { WorkoutShareVideoClip.removeScratch(for: clip.id) }

        XCTAssertNil(WorkoutShareBackgroundPolicy.resolvedVideo(clip, isProUnlocked: false))
        XCTAssertEqual(
            WorkoutShareBackgroundPolicy.resolvedVideo(clip, isProUnlocked: true), clip
        )
        XCTAssertNil(WorkoutShareBackgroundPolicy.resolvedVideo(nil, isProUnlocked: true))
    }

    // MARK: - Integration: export

    /// The whole pipeline at every ratio. Also the preset hypothesis: HighestQuality must
    /// encode at the video composition's `renderSize`, not resize it.
    func testExportProducesCardSizedVideoWithUprightOverlayAtEveryRatio() async throws {
        let scratch = makeScratch()
        let url = try await Self.makeVideoFixture(seconds: 2, audioSeconds: 1, in: scratch)
        let clip = try await WorkoutShareVideoClip.load(url: url)
        defer { WorkoutShareVideoClip.removeScratch(for: clip.id) }
        XCTAssertTrue(clip.hasAudio)

        for ratio in WorkoutShareAspectRatio.allCases {
            let cardSize = ratio.cardSize
            let renderSize = WorkoutShareVideoComposer.renderSize(for: cardSize)
            let overlay = Self.makeOverlay(renderSize: renderSize)

            let output = try await WorkoutShareVideoComposer.export(
                clip: clip, overlay: overlay, cardSize: cardSize, photoTransform: .identity
            )
            let label = ratio.rawValue
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: output.path), "output exists: \(label)"
            )

            let exported = AVURLAsset(url: output)
            let duration = try await exported.load(.duration)
            XCTAssertEqual(duration.seconds, 2, accuracy: 0.2, "duration: \(label)")

            let videoTracks = try await exported.loadTracks(withMediaType: .video)
            let videoTrack = try XCTUnwrap(videoTracks.first, "video track: \(label)")
            let (natural, transform) = try await videoTrack.load(.naturalSize, .preferredTransform)
            let presented = CGRect(origin: .zero, size: natural).applying(transform)
            XCTAssertEqual(abs(presented.width), renderSize.width, accuracy: 1, "width: \(label)")
            XCTAssertEqual(abs(presented.height), renderSize.height, accuracy: 1, "height: \(label)")

            // Codec + SDR BT.709
            let formats = try await videoTrack.load(.formatDescriptions)
            let format = try XCTUnwrap(formats.first, "format description: \(label)")
            XCTAssertEqual(
                CMFormatDescriptionGetMediaSubType(format), kCMVideoCodecType_H264,
                "H.264: \(label)"
            )
            XCTAssertEqual(
                Self.stringExtension(format, kCMFormatDescriptionExtension_ColorPrimaries),
                kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String, "primaries: \(label)"
            )
            XCTAssertEqual(
                Self.stringExtension(format, kCMFormatDescriptionExtension_TransferFunction),
                kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String, "transfer: \(label)"
            )
            XCTAssertEqual(
                Self.stringExtension(format, kCMFormatDescriptionExtension_YCbCrMatrix),
                kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2 as String, "matrix: \(label)"
            )

            // Audio: 1 s of the 2 s clip, at the start.
            let audioTracks = try await exported.loadTracks(withMediaType: .audio)
            let audioTrack = try XCTUnwrap(audioTracks.first, "audio track: \(label)")
            let audioRange = try await audioTrack.load(.timeRange)
            XCTAssertEqual(audioRange.start.seconds, 0, accuracy: 0.1, "audio start: \(label)")
            XCTAssertEqual(
                audioRange.duration.seconds, 1, accuracy: 0.2, "audio duration: \(label)"
            )

            // Orientation: each overlay corner colour must land in its own output corner.
            let frame = try await Self.frame(of: exported, at: CMTime(seconds: 1, preferredTimescale: 600))
            let raster = try Self.raster(frame)
            XCTAssertEqual(raster.width, Int(renderSize.width), "raster width: \(label)")
            XCTAssertEqual(raster.height, Int(renderSize.height), "raster height: \(label)")

            let inset = 40
            Self.assertColor(
                raster.pixel(inset, inset), near: (1, 0, 1), "top-left magenta: \(label)"
            )
            Self.assertColor(
                raster.pixel(raster.width - inset, inset), near: (0, 1, 1),
                "top-right cyan: \(label)"
            )
            Self.assertColor(
                raster.pixel(inset, raster.height - inset), near: (1, 1, 1),
                "bottom-left white: \(label)"
            )
            Self.assertColor(
                raster.pixel(raster.width - inset, raster.height - inset), near: (1, 0.5, 0),
                "bottom-right orange: \(label)"
            )

            // Interior point, clear of the overlay squares: the source's own top-left
            // quadrant (red) fills that part of the card at identity pan/zoom. Looser than
            // the overlay corners — this pixel went through 4:2:0 chroma subsampling twice
            // (fixture encode, then export), which bleeds ~0.15 into the flat channels. Far
            // tighter than the gap to any other quadrant colour, which is what it tests.
            Self.assertColor(
                raster.pixel(Int(renderSize.width * 0.3), Int(renderSize.height * 0.3)),
                near: (1, 0, 0), "video quadrant: \(label)", tolerance: 0.25
            )
        }
    }

    /// A 20 s clip is well under the 60 s cap, so the export keeps it whole rather than
    /// clamping — the cap itself is proven without a fixture by the pure
    /// `exportTimeRange` tests above.
    func testExportKeepsClipsUnderTheCapWholeAndClampsAtSixtySeconds() async throws {
        let scratch = makeScratch()
        let url = try await Self.makeVideoFixture(seconds: 20, audioSeconds: nil, in: scratch)
        let clip = try await WorkoutShareVideoClip.load(url: url)
        defer { WorkoutShareVideoClip.removeScratch(for: clip.id) }

        let cardSize = WorkoutShareAspectRatio.portrait9x16.cardSize
        let overlay = Self.makeOverlay(
            renderSize: WorkoutShareVideoComposer.renderSize(for: cardSize)
        )
        let output = try await WorkoutShareVideoComposer.export(
            clip: clip, overlay: overlay, cardSize: cardSize, photoTransform: .identity
        )
        let duration = try await AVURLAsset(url: output).load(.duration)
        XCTAssertEqual(duration.seconds, 20, accuracy: 0.2)
    }

    /// A silent source stays silent — no empty audio track is invented.
    func testExportOfSilentSourceHasNoAudioTrack() async throws {
        let scratch = makeScratch()
        let url = try await Self.makeVideoFixture(seconds: 2, audioSeconds: nil, in: scratch)
        let clip = try await WorkoutShareVideoClip.load(url: url)
        defer { WorkoutShareVideoClip.removeScratch(for: clip.id) }
        XCTAssertFalse(clip.hasAudio)

        let cardSize = WorkoutShareAspectRatio.portrait9x16.cardSize
        let overlay = Self.makeOverlay(
            renderSize: WorkoutShareVideoComposer.renderSize(for: cardSize)
        )
        let output = try await WorkoutShareVideoComposer.export(
            clip: clip, overlay: overlay, cardSize: cardSize, photoTransform: .identity
        )
        let audioTracks = try await AVURLAsset(url: output).loadTracks(withMediaType: .audio)
        XCTAssertTrue(audioTracks.isEmpty)
    }

    // MARK: - Scratch

    private func makeScratch() -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("WorkoutShareVideoTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}

// MARK: - fillTransform fixtures

extension WorkoutShareVideoTests {
    fileprivate struct Source {
        let name: String
        let naturalSize: CGSize
        let preferredTransform: CGAffineTransform
    }

    fileprivate static let sources: [Source] = [
        Source(name: "portrait", naturalSize: CGSize(width: 1080, height: 1920),
               preferredTransform: .identity),
        Source(name: "landscape", naturalSize: CGSize(width: 1920, height: 1080),
               preferredTransform: .identity),
        // A portrait phone clip: stored landscape, rotated 90° on playback.
        Source(name: "rotated90", naturalSize: CGSize(width: 1920, height: 1080),
               preferredTransform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)),
        // A front-camera clip: mirrored horizontally.
        Source(name: "mirrored", naturalSize: CGSize(width: 1920, height: 1080),
               preferredTransform: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1920, ty: 0))
    ]

    fileprivate static func mappedRect(
        _ source: Source, _ cardSize: CGSize, _ photoTransform: WorkoutSharePhotoTransform
    ) -> CGRect {
        let transform = WorkoutShareVideoComposer.fillTransform(
            naturalSize: source.naturalSize,
            preferredTransform: source.preferredTransform,
            cardSize: cardSize,
            photoTransform: photoTransform
        )
        return CGRect(origin: .zero, size: source.naturalSize).applying(transform)
    }
}

// MARK: - Synthetic media fixtures

extension WorkoutShareVideoTests {
    /// 640×480, 30 fps, four quadrant colours (red TL, green TR, blue BL, yellow BR),
    /// optionally with a silent 44.1 kHz AAC track that is deliberately shorter than
    /// the video so the export's audio range is observable.
    fileprivate static func makeVideoFixture(
        seconds: Double, audioSeconds: Double?, in directory: URL
    ) async throws -> URL {
        let url = directory.appendingPathComponent("fixture-\(UUID().uuidString).mov")
        let width = 640
        let height = 480
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
        )
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if audioSeconds != nil {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVNumberOfChannelsKey: 1,
                    AVSampleRateKey: 44_100,
                    AVEncoderBitRateKey: 64_000
                ]
            )
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audioInput = input
        }

        guard writer.startWriting() else {
            throw writer.error ?? WorkoutShareVideoError.noVideoTrack
        }
        writer.startSession(atSourceTime: .zero)

        // Both inputs have to advance together: an `AVAssetWriter` stops accepting data on
        // one input while another lags far behind it, so writing all the video first and
        // the audio afterwards deadlocks on `isReadyForMoreMediaData`.
        let buffer = try makeQuadrantPixelBuffer(width: width, height: height)
        let frameCount = Int((seconds * 30).rounded())
        let audio = try audioInput.map { input in
            (input: input, silence: try SilenceWriter(seconds: audioSeconds ?? 0))
        }
        var isAudioFinished = false
        for frame in 0..<frameCount {
            let time = CMTime(value: CMTimeValue(frame), timescale: 30)
            if let audio, !isAudioFinished {
                try await audio.silence.append(upTo: time.seconds, to: audio.input)
                if audio.silence.isDrained {
                    audio.input.markAsFinished()
                    isAudioFinished = true
                }
            }
            try await waitForReady(videoInput)
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: time))
        }
        videoInput.markAsFinished()

        if let audio, !isAudioFinished {
            try await audio.silence.append(upTo: .infinity, to: audio.input)
            audio.input.markAsFinished()
        }

        writer.endSession(atSourceTime: CMTime(seconds: seconds, preferredTimescale: 600))
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? WorkoutShareVideoError.noVideoTrack }
        return url
    }

    /// One frame, with the session ended where it started: a video track whose duration
    /// is zero, which `load` must refuse.
    fileprivate static func makeZeroDurationFixture(in directory: URL) async throws -> URL {
        let url = directory.appendingPathComponent("empty-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 64,
                AVVideoHeightKey: 64
            ]
        )
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64
            ]
        )
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? WorkoutShareVideoError.noVideoTrack
        }
        writer.startSession(atSourceTime: .zero)
        let buffer = try makeQuadrantPixelBuffer(width: 64, height: 64)
        while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
        _ = adaptor.append(buffer, withPresentationTime: .zero)
        input.markAsFinished()
        writer.endSession(atSourceTime: .zero)
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? WorkoutShareVideoError.noVideoTrack }
        return url
    }

    /// An audio-only file: nothing for `load` to render.
    fileprivate static func makeAudioOnlyFixture(
        seconds: Double, in directory: URL
    ) async throws -> URL {
        let url = directory.appendingPathComponent("audio-\(UUID().uuidString).m4a")
        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 64_000
            ]
        )
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? WorkoutShareVideoError.noVideoTrack
        }
        writer.startSession(atSourceTime: .zero)
        try await SilenceWriter(seconds: seconds).append(upTo: .infinity, to: input)
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: seconds, preferredTimescale: 600))
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? WorkoutShareVideoError.noVideoTrack }
        return url
    }

    /// Feeds an AAC-configured input zeroed 16-bit mono LPCM, a chunk at a time, so the
    /// caller can keep it in step with the video input instead of writing it in one burst.
    fileprivate final class SilenceWriter {
        private static let sampleRate = 44_100.0
        private let formatDescription: CMAudioFormatDescription
        private let totalFrames: Int
        private var written = 0

        /// True once every sample has been appended — the caller must then finish the
        /// input, or the writer stalls the video input waiting for audio that never comes.
        var isDrained: Bool { written >= totalFrames }

        init(seconds: Double) throws {
            var asbd = AudioStreamBasicDescription(
                mSampleRate: Self.sampleRate,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                mBytesPerPacket: 2,
                mFramesPerPacket: 1,
                mBytesPerFrame: 2,
                mChannelsPerFrame: 1,
                mBitsPerChannel: 16,
                mReserved: 0
            )
            var description: CMAudioFormatDescription?
            guard CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
                magicCookieSize: 0, magicCookie: nil, extensions: nil,
                formatDescriptionOut: &description
            ) == noErr, let description else {
                throw WorkoutShareVideoError.unusableDuration
            }
            formatDescription = description
            totalFrames = Int(seconds * Self.sampleRate)
        }

        /// Appends every chunk that starts at or before `seconds` (pass `.infinity` to flush).
        func append(upTo seconds: Double, to input: AVAssetWriterInput) async throws {
            let chunkFrames = 1024
            while written < totalFrames, Double(written) / Self.sampleRate <= seconds {
                let frames = min(chunkFrames, totalFrames - written)
                let byteCount = frames * 2
                var blockBuffer: CMBlockBuffer?
                guard CMBlockBufferCreateWithMemoryBlock(
                    allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: byteCount,
                    blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                    offsetToData: 0, dataLength: byteCount,
                    flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &blockBuffer
                ) == noErr, let blockBuffer else {
                    throw WorkoutShareVideoError.unusableDuration
                }
                CMBlockBufferFillDataBytes(
                    with: 0, blockBuffer: blockBuffer,
                    offsetIntoDestination: 0, dataLength: byteCount
                )

                var sampleBuffer: CMSampleBuffer?
                guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                    allocator: kCFAllocatorDefault, dataBuffer: blockBuffer,
                    formatDescription: formatDescription, sampleCount: CMItemCount(frames),
                    presentationTimeStamp: CMTime(
                        value: CMTimeValue(written), timescale: CMTimeScale(Self.sampleRate)
                    ),
                    packetDescriptions: nil, sampleBufferOut: &sampleBuffer
                ) == noErr, let sampleBuffer else {
                    throw WorkoutShareVideoError.unusableDuration
                }

                try await WorkoutShareVideoTests.waitForReady(input)
                XCTAssertTrue(input.append(sampleBuffer))
                written += frames
            }
        }
    }

    /// Bounded, so a writer that stops accepting data fails the test instead of hanging it.
    fileprivate static func waitForReady(_ input: AVAssetWriterInput) async throws {
        for _ in 0..<5_000 {
            if input.isReadyForMoreMediaData { return }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("AVAssetWriterInput never became ready for more media data")
        throw WorkoutShareVideoError.unusableDuration
    }

    /// Four flat quadrants written straight into the buffer, so "top" is unambiguously
    /// memory row 0 rather than whatever a `CGContext` flip would give us.
    private static func makeQuadrantPixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary, &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            throw WorkoutShareVideoError.noVideoTrack
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            throw WorkoutShareVideoError.noVideoTrack
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let pointer = base.assumingMemoryBound(to: UInt8.self)
        // BGRA quadrants: red, green / blue, yellow.
        let topLeft: (UInt8, UInt8, UInt8) = (0, 0, 255)
        let topRight: (UInt8, UInt8, UInt8) = (0, 255, 0)
        let bottomLeft: (UInt8, UInt8, UInt8) = (255, 0, 0)
        let bottomRight: (UInt8, UInt8, UInt8) = (0, 255, 255)
        for row in 0..<height {
            let isTop = row < height / 2
            for column in 0..<width {
                let isLeft = column < width / 2
                let colour = isTop
                    ? (isLeft ? topLeft : topRight)
                    : (isLeft ? bottomLeft : bottomRight)
                let offset = row * bytesPerRow + column * 4
                pointer[offset] = colour.0
                pointer[offset + 1] = colour.1
                pointer[offset + 2] = colour.2
                pointer[offset + 3] = 255
            }
        }
        return buffer
    }

    /// Transparent, with a 150 px square of a distinct colour in each corner — the only
    /// way to tell an upright overlay from a vertically flipped one.
    fileprivate static func makeOverlay(renderSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: renderSize, format: format).image { context in
            let side: CGFloat = 150
            UIColor.magenta.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            UIColor.cyan.setFill()
            context.fill(CGRect(x: renderSize.width - side, y: 0, width: side, height: side))
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: renderSize.height - side, width: side, height: side))
            UIColor.orange.setFill()
            context.fill(
                CGRect(
                    x: renderSize.width - side, y: renderSize.height - side,
                    width: side, height: side
                )
            )
        }
    }
}

// MARK: - Frame inspection

extension WorkoutShareVideoTests {
    fileprivate struct Raster {
        let bytes: [UInt8]
        let width: Int
        let height: Int

        /// Clamped so a corner sample expressed as `width - inset` stays in bounds.
        func pixel(_ x: Int, _ y: Int) -> (CGFloat, CGFloat, CGFloat) {
            let column = min(max(x, 0), width - 1)
            let row = min(max(y, 0), height - 1)
            let offset = (row * width + column) * 4
            return (
                CGFloat(bytes[offset]) / 255,
                CGFloat(bytes[offset + 1]) / 255,
                CGFloat(bytes[offset + 2]) / 255
            )
        }
    }

    fileprivate static func frame(of asset: AVAsset, at time: CMTime) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: time).image
    }

    fileprivate static func raster(_ image: CGImage) throws -> Raster {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw WorkoutShareVideoError.noVideoTrack
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Raster(bytes: bytes, width: width, height: height)
    }

    fileprivate static func stringExtension(
        _ format: CMFormatDescription, _ key: CFString
    ) -> String? {
        CMFormatDescriptionGetExtension(format, extensionKey: key) as? String
    }

    /// H.264 through a limited-range BT.709 round trip never comes back exact.
    fileprivate static func assertColor(
        _ actual: (CGFloat, CGFloat, CGFloat),
        near expected: (CGFloat, CGFloat, CGFloat),
        _ message: String,
        tolerance: CGFloat = 0.12,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.0, expected.0, accuracy: tolerance, "\(message) red", file: file, line: line)
        XCTAssertEqual(actual.1, expected.1, accuracy: tolerance, "\(message) green", file: file, line: line)
        XCTAssertEqual(actual.2, expected.2, accuracy: tolerance, "\(message) blue", file: file, line: line)
    }
}
