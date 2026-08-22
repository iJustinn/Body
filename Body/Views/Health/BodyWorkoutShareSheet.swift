//
//  BodyWorkoutShareSheet.swift
//  Body
//
//  Preview-and-share flow for a workout's image or video. Built like a story composer:
//  the card fills the page scaled to fit whatever shape the chosen aspect ratio gives
//  it, a vertical icon rail sits on the trailing edge, and tapping a rail icon slides
//  that option's tiles out to its left (Font, Route Color, Route Style, Background,
//  Ratio, Arrange — one tray open at a time); Metrics, fourth down the rail, opens a
//  chip strip under the card instead. Save/Share rasterize the card via
//  `ImageRenderer` at 3×
//  and hand the image (1080 px on its short side) to the photo library or the system
//  share sheet. On a video background the same rasterization becomes a transparent
//  overlay `WorkoutShareVideoComposer` holds over the clip's first 60 s, and the
//  export is an MP4 instead. On a photo or video background the preview drives two
//  adjust steps: Photo/Video pans/zooms the backdrop, Layout moves and resizes the
//  card's info block — both session-only, and both fed to the export so what ships
//  matches the preview. The
//  A sixth tile in the Ratio tray switches the whole output to the Pro "long image"
//  instead: the detail page's tiles and charts as one naturally tall picture, always on
//  a gradient preset (map/photo/video tiles go inert), with the metric chips picking
//  what it contains and no five-metric cap. The
//  route is optional: a workout without one (indoor, strength, yoga…) shares the same
//  flow with the map tile and the Route Color / Arrange / 3D rail icons dropped and
//  the card's route-less layout in place of the trace.
//

import SwiftUI
import AVFoundation
import PhotosUI
import Photos
import ImageIO
import MapKit
import UIKit

struct BodyWorkoutShareSheet: View {
    let workout: WorkoutSummary
    let route: WorkoutRoute?
    let presentation: WorkoutDetailPresentation
    /// Everything the long image's chart sections need, handed over by the detail page
    /// rather than refetched — a workout under 24 h old would re-query HealthKit for
    /// series that page already has. All four have empty/nil sentinels, so a caller that
    /// doesn't build them (a preview, a test) simply gets a long image without charts.
    let splitData: WorkoutSplitData
    let metricSeries: WorkoutMetricSeriesData
    /// Age-estimated max HR, for the heart-rate card's zone bands.
    let maxHeartRate: Double?
    /// Loads separately from the workout's own statistics, so it can arrive after the
    /// sheet is already up — the pool and the tile list are rebuilt when it does.
    let heartRateRecoveryBPM: Double?

    @Environment(BodyProStore.self) private var proStore: BodyProStore?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(BodyWorkoutShareBackgroundChoice.storageKey) private var storedBackground: String =
        BodyWorkoutShareBackgroundChoice.preset(.midnight).rawValue
    @AppStorage(WorkoutShareRouteDimension.storageKey) private var storedDimension: String =
        WorkoutShareRouteDimension.twoD.rawValue
    @AppStorage(WorkoutShareRouteVisibility.storageKey) private var storedRouteVisibility: String =
        WorkoutShareRouteVisibility.shown.rawValue
    @AppStorage(WorkoutShareIconVisibility.storageKey) private var storedIconVisibility: String =
        WorkoutShareIconVisibility.shown.rawValue
    @AppStorage(WorkoutShareAvatarVisibility.storageKey) private var storedAvatarVisibility: String =
        WorkoutShareAvatarVisibility.hidden.rawValue
    @AppStorage(WorkoutShareNicknameVisibility.storageKey) private var storedNicknameVisibility: String =
        WorkoutShareNicknameVisibility.hidden.rawValue
    @AppStorage(WorkoutShareSeparatorVisibility.storageKey) private var storedSeparatorVisibility: String =
        WorkoutShareSeparatorVisibility.shown.rawValue
    /// Mirrors `BodyProfileView`'s own storage exactly — same keys, same defaults — so
    /// the sheet reads whatever Settings › Profile currently has on hand.
    @AppStorage(BodyAppearancePreference.profileNameKey) private var profileName = ""
    @AppStorage(BodyAppearancePreference.profileAvatarDataKey) private var profileAvatarData = Data()
    @AppStorage(WorkoutShareFontChoice.storageKey) private var storedFont: String =
        WorkoutShareFontChoice.rounded.rawValue
    @AppStorage(WorkoutShareRouteColorChoice.storageKey) private var storedRouteColor: String =
        WorkoutShareRouteColorChoice.bodyBlue.rawValue
    @AppStorage(WorkoutShareAspectRatio.storageKey) private var storedAspectRatio: String =
        WorkoutShareAspectRatio.portrait9x16.rawValue
    @AppStorage(WorkoutShareLandscapeArrangement.storageKey) private var storedArrangement: String =
        WorkoutShareLandscapeArrangement.stacked.rawValue
    /// Every workout type's remembered metric pick in one JSON blob — see
    /// `WorkoutShareMetricSelection`. Empty means nobody has picked yet, which is the
    /// same thing a non-Pro user gets: the automatic defaults.
    @AppStorage(WorkoutShareMetricSelection.storageKey) private var storedMetricSelections: String = ""
    /// The long image's own pick, under its own key — it has no five-metric ceiling and
    /// defaults to every metric, so it can't share the card's blob.
    @AppStorage(WorkoutShareMetricSelection.longStorageKey) private var storedLongMetricSelections: String = ""
    /// Card or long image. Pro-gated through `resolvedOutputStyle`, so a lapse falls
    /// back to the card for the session without rewriting the key.
    @AppStorage(WorkoutShareOutputStyle.storageKey) private var storedOutputStyle: String =
        WorkoutShareOutputStyle.card.rawValue
    /// The long image's charts are unit-sensitive (splits, elevation, pace), and they
    /// have to read the same preference the detail page just showed the user.
    @AppStorage(BodyAppearancePreference.followsSystemUnitsKey) private var followsSystemUnits = true
    @AppStorage(BodyAppearancePreference.selectedDistanceUnitKey) private var selectedDistanceUnitRawValue =
        BodyValueFormat.DistanceUnitPreference.defaultValue.rawValue

    /// The session-only backdrop, as one value so photo and video can't both be held:
    /// picking either replaces the other, and the two accessors below keep every
    /// existing "is there a photo" read spelled the way it always was.
    private enum SelectedMedia: Equatable {
        case photo(UIImage)
        case video(WorkoutShareVideoClip)
    }

    @State private var selectedMedia: SelectedMedia?
    @State private var photoItem: PhotosPickerItem?
    @State private var isPickerPresented = false
    @State private var isLoadingPhoto = false
    @State private var videoItem: PhotosPickerItem?
    @State private var isVideoPickerPresented = false
    @State private var isLoadingVideo = false
    /// A queue player plus its looper, so the preview repeats exactly the range the
    /// export will cut. Held together: the looper is what keeps items coming, and
    /// releasing it without stopping the player leaves a half-driven queue behind.
    @State private var previewPlayer: AVQueuePlayer?
    @State private var previewLooper: AVPlayerLooper?
    /// The in-flight composite, for both Share and Save — cancelled by Close and by
    /// anything that replaces the clip under it.
    @State private var videoExportTask: Task<Void, Never>?
    @State private var showVideoLoadError = false
    @State private var showVideoExportError = false
    @State private var showVideoSaveError = false
    @State private var videoPayload: WorkoutShareVideoPayload?
    /// Clips whose scratch directory is retired but still readable by something the
    /// user hasn't finished with — the activity sheet holding the exported URL, or a
    /// save in flight. Emptied as soon as both are done (and on dismissal).
    @State private var pendingScratchIDs: [UUID] = []
    /// Which rail tray is open, if any — one at a time, so the trays never stack up
    /// over the card.
    @State private var expandedOption: RailOption?
    /// One snapshot per dimension *and* ratio: 2D composites the flat route onto the
    /// roads, 3D the lifted ribbon, each ratio frames a differently shaped region, and
    /// the snapshot is baked at the card's own pixel size — so no other key's image can
    /// stand in, and none is thrown away when the user switches back. Session-only,
    /// like the failure set below.
    @State private var mapSnapshots: [MapSnapshotKey: UIImage] = [:]
    @State private var loadingMapKeys: Set<MapSnapshotKey> = []
    /// A snapshot failure is session-only: the stored choice stays `.map`, so a
    /// transient failure (offline, say) doesn't discard the user's background — the
    /// next open retries it — while this sheet shows Midnight in the meantime.
    @State private var failedMapKeys: Set<MapSnapshotKey> = []
    @State private var showBodyProPaywall = false
    @State private var showPhotoLoadError = false
    @State private var showMapLoadError = false
    @State private var showRenderError = false
    @State private var showSaveError = false
    @State private var isPhotoAccessDenied = false
    @State private var isRendering = false
    @State private var isSavingImage = false
    @State private var didSave = false
    @State private var payload: WorkoutSharePayload?
    /// Where the user has dragged/pinched the info block, between gestures.
    @State private var committedInfoTransform = WorkoutShareInfoTransform.identity
    /// Where the user has dragged/pinched the photo behind it, between gestures.
    @State private var photoTransform = WorkoutSharePhotoTransform.identity
    /// The live drag+pinch, held as one value so a single `.updating` on the composite
    /// gesture owns both halves. Shared by both adjust steps — only one of them is
    /// wired to the gesture at a time, so one in-flight value is enough.
    @GestureState private var inFlightGesture = WorkoutShareInfoGesture.idle
    /// The long card's measured natural height, so the preview's scroll view can size
    /// the scaled copy. Zero until the first layout pass fills it in.
    @State private var longCardHeight: CGFloat = 0
    /// Which of the two things the photo preview's gestures move. Photo comes first: the
    /// backdrop has to be framed before placing the block on it makes sense.
    @State private var photoStep: PhotoAdjustStep = .photo
    /// The decoded profile avatar, held rather than computed: `cardView()` re-evaluates
    /// on every drag/pinch frame, and decoding the JPEG that often would be wasted work.
    /// Seeded in `.task` and kept in sync with `profileAvatarData` via `.onChange`.
    @State private var profileAvatarImage: UIImage?

    /// Computed once from the shared presentation so the card's values never drift
    /// from the detail page and the projection isn't redone on every body pass.
    /// The pool the Metrics tray offers and the card resolves against, plus what the
    /// card shows when nobody picked. Both depend only on the presentation and the
    /// route's presence, so they're built once here rather than per body pass.
    private let availableMetricOptions: [WorkoutShareMetricOption]
    private let defaultMetricIDs: [String]
    /// The Details tiles the long image can draw, in Details order and with their
    /// comparison badges intact — `WorkoutShareMetric` strips those, so the long image
    /// maps ids onto these instead. Built alongside the pool so the two always agree
    /// about whether HR Recovery has landed.
    private let longTilePool: [WorkoutDetailMetric]
    private let routePoints: [CGPoint]?
    /// The elevation ribbon at rest (yaw 0) — `nil` when the route can't carry one, which
    /// is also what makes the 3D row unavailable.
    private let route3D: WorkoutRoute3DProjection.Projected3D?

    private enum PhotoAdjustStep: Hashable {
        case photo
        case layout
    }

    /// One rail icon each, top to bottom. `CaseIterable` isn't what draws the rail (the
    /// rows have their own visibility rules), it's what keeps the set enumerable.
    private enum RailOption: Hashable, CaseIterable {
        case font
        case metrics
        case profile
        case ratio
        case arrange
        case routeColor
        case background
        case dimension
    }

    /// A cached map snapshot's identity: the dimension decides what is composited and
    /// how the region is framed, the ratio decides the snapshot's shape and pixel size.
    private struct MapSnapshotKey: Hashable {
        let dimension: WorkoutShareRouteDimension
        let aspectRatio: WorkoutShareAspectRatio
    }

    /// The four long-image inputs are defaulted, so every existing call site (and the
    /// previews/tests) still constructs the sheet with three arguments and simply gets a
    /// long image with no chart sections.
    ///
    /// The pool and tile list are built here rather than lazily *because* this runs
    /// again on every re-presentation pass: the detail page's `fullScreenCover` closure
    /// re-evaluates while the sheet is up, so an HR-recovery value that lands afterwards
    /// arrives as a new sheet value and rebuilds both — no per-body-pass cost, and no
    /// stale pool either.
    init(
        workout: WorkoutSummary,
        route: WorkoutRoute?,
        presentation: WorkoutDetailPresentation,
        splitData: WorkoutSplitData = .empty,
        metricSeries: WorkoutMetricSeriesData = .empty,
        maxHeartRate: Double? = nil,
        heartRateRecoveryBPM: Double? = nil
    ) {
        self.workout = workout
        self.route = route
        self.presentation = presentation
        self.splitData = splitData
        self.metricSeries = metricSeries
        self.maxHeartRate = maxHeartRate
        self.heartRateRecoveryBPM = heartRateRecoveryBPM

        var options = WorkoutShareMetricsBuilder.availableMetrics(for: presentation, type: workout.type)
        var tiles = presentation.detailMetrics
        // Mirrors the detail page's own trailing tile: HR recovery joins the grid when
        // it lands, and is skipped when the workout's statistics already carried it.
        if let heartRateRecoveryBPM, !tiles.contains(where: { $0.kind == .heartRateRecovery }) {
            let tile = WorkoutDetailPresentation.heartRateRecoveryMetric(bpm: heartRateRecoveryBPM)
            tiles.append(tile)
            options.append(WorkoutShareMetricOption(
                id: WorkoutShareMetricOption.key(for: .heartRateRecovery),
                tileTitle: tile.title,
                value: tile.value,
                kind: .heartRateRecovery
            ))
        }
        self.availableMetricOptions = options
        self.longTilePool = tiles
        self.defaultMetricIDs = WorkoutShareMetricsBuilder.defaultMetricIDs(
            for: presentation,
            type: workout.type,
            hasRoute: route != nil
        )
        self.routePoints = route.flatMap { WorkoutShareRouteProjection.normalizedPoints(for: $0.coordinates) }
        self.route3D = route.flatMap { WorkoutRoute3DProjection.projected(for: $0.coordinates) }
    }

    private var isProUnlocked: Bool { proStore?.isPro == true }

    private var selectedPhoto: UIImage? {
        if case .photo(let image) = selectedMedia { return image }
        return nil
    }

    private var selectedVideo: WorkoutShareVideoClip? {
        if case .video(let clip) = selectedMedia { return clip }
        return nil
    }

    /// The backdrop's own point size, whichever kind it is — the one input both the
    /// live clamp and the gesture-commit clamp read, so a video's overhang is bounded
    /// exactly the way a photo's is.
    private var activeMediaSize: CGSize {
        selectedPhoto?.size ?? selectedVideo?.orientedSize ?? .zero
    }

    /// What the card is actually showing right now: the remembered pick narrowed to
    /// this workout's tiles, or the automatic defaults when nothing survives — and
    /// always the defaults without Pro, without touching what's stored.
    private var activeMetricIDs: [String] {
        WorkoutShareBackgroundPolicy.resolvedMetricIDs(
            WorkoutShareMetricSelection.resolved(
                stored: WorkoutShareMetricSelection.stored(json: storedMetricSelections, type: workout.type),
                available: availableMetricOptions,
                defaults: defaultMetricIDs
            ),
            defaults: defaultMetricIDs,
            isProUnlocked: isProUnlocked
        )
    }

    /// The long image's pick: everything unless the user narrowed it. No Pro resolution
    /// of its own — the mode is Pro-gated, so a non-Pro user never sees these chips.
    private var activeLongMetricIDs: [String] {
        WorkoutShareMetricSelection.resolvedLong(
            stored: WorkoutShareMetricSelection.stored(json: storedLongMetricSelections, type: workout.type),
            available: availableMetricOptions
        )
    }

    /// What Share and Save actually produce. Pro-gated, session-only: a lapse renders
    /// the card without rewriting the stored style.
    private var activeOutputStyle: WorkoutShareOutputStyle {
        WorkoutShareBackgroundPolicy.resolvedOutputStyle(
            WorkoutShareOutputStyle.stored(rawValue: storedOutputStyle),
            isProUnlocked: isProUnlocked
        )
    }

    private var isLongMode: Bool { activeOutputStyle == .longImage }

    /// The gradient the long image paints — any stored preset (Midnight, Workout
    /// Color, or Daylight) shows through untouched even while a photo or clip is held,
    /// since the long image never draws either; only a stored map falls back to
    /// Midnight, which the long image also never draws. The preview ring, the export,
    /// and the save all read this one value.
    private var activeLongPreset: BodyWorkoutSharePreset {
        WorkoutShareBackgroundPolicy.longPreset(storedBackground: storedBackground, hasRoute: hasRoute)
    }

    private var hasRoute: Bool { route != nil }

    /// The route carries enough altitude for a ribbon. Without it the 3D row is shown
    /// greyed out and untappable rather than hidden, so the option stays discoverable.
    private var isThreeDAvailable: Bool { route3D != nil }

    /// The dimension the card actually draws — the stored one only when Pro and the
    /// route can carry a ribbon. Session-only fallback: the key is never rewritten.
    private var activeDimension: WorkoutShareRouteDimension {
        WorkoutShareBackgroundPolicy.resolvedDimension(
            WorkoutShareRouteDimension.stored(rawValue: storedDimension),
            isProUnlocked: isProUnlocked,
            isThreeDAvailable: isThreeDAvailable
        )
    }

    /// Whether the card-drawn trace is hidden. Free, so nothing to resolve; the map
    /// background ignores it (its route is part of the snapshot), and the tile is
    /// disabled there so the stored choice can't silently mean nothing.
    private var isRouteHidden: Bool {
        WorkoutShareRouteVisibility.stored(rawValue: storedRouteVisibility) == .hidden
    }

    /// Whether the route-less card's type glyph is hidden. Free, like the route
    /// visibility it mirrors; only ever consulted on a route-less card.
    private var isIconHidden: Bool {
        WorkoutShareIconVisibility.stored(rawValue: storedIconVisibility) == .hidden
    }

    /// The Settings profile name, trimmed and nil-if-empty — the same rule the profile
    /// page itself uses.
    private var profileDisplayName: String? {
        BodyUserProfile.displayName(from: profileName)
    }

    private var isAvatarShown: Bool {
        WorkoutShareAvatarVisibility.stored(rawValue: storedAvatarVisibility) == .shown
    }

    private var isNicknameShown: Bool {
        WorkoutShareNicknameVisibility.stored(rawValue: storedNicknameVisibility) == .shown
    }

    private var isSeparatorShown: Bool {
        WorkoutShareSeparatorVisibility.stored(rawValue: storedSeparatorVisibility) == .shown
    }

    /// What the card actually draws beside the watermark — a toggle that's on but whose
    /// backing data has since been deleted in Settings draws nothing for that field.
    private var activeAttribution: WorkoutShareAttribution {
        WorkoutShareAttribution(
            avatar: isAvatarShown ? profileAvatarImage : nil,
            name: isNicknameShown ? profileDisplayName : nil,
            showsSeparator: isSeparatorShown
        )
    }

    /// The shape the card actually renders at — the stored one only when it's free or
    /// the user is Pro. Session-only fallback: the key is never rewritten, so a lapsed
    /// subscriber shares at 9:16 and gets their ratio back on resubscribe.
    private var activeAspectRatio: WorkoutShareAspectRatio {
        WorkoutShareBackgroundPolicy.resolvedAspectRatio(
            WorkoutShareAspectRatio.stored(rawValue: storedAspectRatio),
            isProUnlocked: isProUnlocked
        )
    }

    /// Free, and only consulted by a landscape centered layout — the card ignores it
    /// everywhere else, so there's nothing to resolve here.
    private var activeArrangement: WorkoutShareLandscapeArrangement {
        WorkoutShareLandscapeArrangement.stored(rawValue: storedArrangement)
    }

    /// The card's point size: preview box, export frame, gesture divisor, and every
    /// transform clamp read this one value so they can't disagree about the shape.
    private var cardSize: CGSize { activeAspectRatio.cardSize }

    private var storedFontChoice: WorkoutShareFontChoice {
        WorkoutShareFontChoice.stored(rawValue: storedFont)
    }

    private var storedRouteColorChoice: WorkoutShareRouteColorChoice {
        WorkoutShareRouteColorChoice.stored(rawValue: storedRouteColor)
    }

    /// The snapshot the card would draw right now — dimension *and* ratio; no other
    /// key's cached image ever stands in for it.
    private var activeMapKey: MapSnapshotKey {
        MapSnapshotKey(dimension: activeDimension, aspectRatio: activeAspectRatio)
    }

    private var activeMapSnapshot: UIImage? { mapSnapshots[activeMapKey] }

    /// What the sheet restores on open — the map unless a preset was last picked, and
    /// never the map without a route to draw.
    private var selectedChoice: BodyWorkoutShareBackgroundChoice {
        BodyWorkoutShareBackgroundChoice.stored(rawValue: storedBackground, hasRoute: hasRoute)
    }

    /// The persisted choice is not the same thing as what's on screen: a session-only
    /// photo sits on top of it. Everything that means "what the user is looking at" —
    /// the strip's highlights, the action bar's disable condition, a map load's failure
    /// branch — reads `activeSelection` so a photo over a stored `.map` behaves right.
    private enum ActiveSelection: Equatable {
        case photo
        case video
        case map
        case preset(BodyWorkoutSharePreset)
    }

    /// `.map` is unreachable without a route: `selectedChoice` already resolves a
    /// stored map to Midnight there, so the layout, the busy state, and the opening
    /// map load all fall out of this one property with no route-less branching.
    private var activeSelection: ActiveSelection {
        if renderablePhoto != nil { return .photo }
        if renderableVideo != nil { return .video }
        if case .preset(let preset) = selectedChoice { return .preset(preset) }
        // Stored choice is the map, but this session couldn't snapshot the combination
        // on screen. Another dimension's or ratio's failure doesn't count — each has
        // its own snapshot to fail.
        if failedMapKeys.contains(activeMapKey) { return .preset(.midnight) }
        return .map
    }

    /// Keyed off the gated photo, not the raw selection: if the Pro entitlement
    /// lapses while a photo is held, the preview falls back to the preset and the
    /// strip's selection highlight must follow it.
    private var isPhotoActive: Bool { renderablePhoto != nil }

    /// The photo that will actually render — passes through the Pro seam in both the
    /// preview and the export so a non-Pro user can never render a photo.
    private var renderablePhoto: UIImage? {
        WorkoutShareBackgroundPolicy.resolvedPhoto(selectedPhoto, isProUnlocked: isProUnlocked)
    }

    /// The clip that will actually render, through the same Pro seam as the photo —
    /// the preview player is paused (not torn down) when this goes nil, so a restored
    /// entitlement picks the clip straight back up.
    private var renderableVideo: WorkoutShareVideoClip? {
        WorkoutShareBackgroundPolicy.resolvedVideo(selectedVideo, isProUnlocked: isProUnlocked)
    }

    /// Whether the backdrop is the user's own media, and so pannable/zoomable with the
    /// two adjust steps. The card is identical in both cases; only the layer under it
    /// differs.
    private var isMediaMode: Bool {
        activeSelection == .photo || activeSelection == .video
    }

    /// The background both preview and export use: photo wins, then the preset, then
    /// the map's snapshot.
    private var activeBackground: WorkoutShareCardBackground {
        if let renderablePhoto {
            return .photo(renderablePhoto)
        }
        if renderableVideo != nil {
            return .video
        }
        if case .preset(let preset) = selectedChoice {
            return .preset(preset)
        }
        if let activeMapSnapshot {
            return .map(activeMapSnapshot)
        }
        // The map is active but hasn't snapshotted yet, and there's no "last preset"
        // to fall back to — Midnight is the same visual the load state always showed.
        return .preset(.midnight)
    }

    /// Which way the card's ink runs, read from `activeBackground` — never from stored
    /// state — so a photo, a map snapshot, or a video frame always takes the light ink
    /// even while a Daylight preset stays selected in the tray. Mirrors the card view's
    /// own `ink` so the preview's forced colour scheme matches what it draws.
    private var activeInk: WorkoutShareCardInk {
        switch activeBackground {
        case .preset(let preset): return preset.ink
        case .photo, .map, .video: return .light
        }
    }

    /// Only the map keeps the classic card. Keyed off `activeSelection`, never
    /// `activeBackground`: while a map snapshot loads, the background reports Midnight,
    /// and deriving from it would flash the centered layout before the map lands. A
    /// *failed* map load is the other way around — the selection itself becomes the
    /// Midnight preset, which is centered on purpose. Without a route no background
    /// changes the answer: the route-less layout is the only one that fits.
    private var cardLayout: WorkoutShareCardLayout {
        guard hasRoute else { return .routeless }
        switch activeSelection {
        case .preset, .photo, .video: return .centered
        case .map: return .classic
        }
    }

    /// Where the info block sits, for the preview and the export alike. Only the user's
    /// own media is repositionable, and anything else reports the identity placement —
    /// so a preset, the map, or a Pro entitlement that lapses while a photo or clip is
    /// still held can never render a transform the user isn't looking at.
    private var activeInfoTransform: WorkoutShareInfoTransform {
        guard isMediaMode else { return .identity }
        // The in-flight value belongs to whichever step is wired to the gesture.
        let live = photoStep == .layout ? inFlightGesture : .idle
        return Self.merged(committedInfoTransform, with: live).clamped(cardSize: cardSize)
    }

    /// How the media backdrop is framed, for the preview and the export alike. Only the
    /// user's own photo or clip can be panned/zoomed; everything else reports the
    /// identity, so a preset, the map, or a lapsed entitlement can never render a
    /// framing the user isn't looking at.
    private var activePhotoTransform: WorkoutSharePhotoTransform {
        guard isMediaMode else { return .identity }
        let live = photoStep == .photo ? inFlightGesture : .idle
        return Self.merged(photoTransform, with: live)
            .clamped(imageSize: activeMediaSize, cardSize: cardSize)
    }

    private static func merged(
        _ transform: WorkoutShareInfoTransform,
        with gesture: WorkoutShareInfoGesture
    ) -> WorkoutShareInfoTransform {
        WorkoutShareInfoTransform(
            offset: CGSize(
                width: transform.offset.width + gesture.translation.width,
                height: transform.offset.height + gesture.translation.height
            ),
            scale: transform.scale * gesture.magnification
        )
    }

    private static func merged(
        _ transform: WorkoutSharePhotoTransform,
        with gesture: WorkoutShareInfoGesture
    ) -> WorkoutSharePhotoTransform {
        WorkoutSharePhotoTransform(
            offset: CGSize(
                width: transform.offset.width + gesture.translation.width,
                height: transform.offset.height + gesture.translation.height
            ),
            scale: transform.scale * gesture.magnification
        )
    }

    private func cardView() -> BodyWorkoutShareCardView {
        // Resolved once per card, not once per array: this runs on every gesture frame,
        // and each read of `activeMetricIDs` decodes the stored JSON.
        let ids = activeMetricIDs
        return BodyWorkoutShareCardView(
            presentation: presentation,
            // A route-less workout only ever draws the block layout — the classic row is
            // unreachable, so it stays empty.
            metrics: route == nil ? [] : WorkoutShareMetricsBuilder.classicRowMetrics(
                selectedIDs: ids,
                available: availableMetricOptions,
                presentation: presentation,
                type: workout.type
            ),
            centeredMetrics: ids.compactMap { id in
                availableMetricOptions.first { $0.id == id }?.centeredMetric
            },
            // Hidden is the traceless centered card: the metrics stand alone, exactly
            // as they do for a route that projects to nothing.
            routePoints: isRouteHidden ? nil : routePoints,
            route3D: isRouteHidden ? nil : route3D,
            dimension: activeDimension,
            iconHidden: isIconHidden && cardLayout == .routeless,
            locality: route?.locality,
            type: workout.type,
            background: activeBackground,
            layout: cardLayout,
            aspectRatio: activeAspectRatio,
            arrangement: activeArrangement,
            infoTransform: activeInfoTransform,
            photoTransform: activePhotoTransform,
            fontDesign: storedFontChoice.design,
            routeColor: storedRouteColorChoice.color(tint: workout.type.color),
            attribution: activeAttribution
        )
    }

    /// The unit the long image's splits, elevation, and pace are drawn in — the same
    /// preference the detail page just used, so the export matches the page.
    private var distanceUnitPreference: BodyValueFormat.DistanceUnitPreference {
        followsSystemUnits
            ? BodyValueFormat.DistanceUnitPreference.systemValue(locale: .current)
            : BodyValueFormat.DistanceUnitPreference.storedValue(from: selectedDistanceUnitRawValue)
    }

    /// Built through the same pure functions the detail page's cards read, so a long
    /// image is the page rather than a second rendering of the same numbers.
    private var longPaceOrSpeed: WorkoutBucketedSeriesPresentation? {
        WorkoutDetailChartPresentations.paceOrSpeed(
            workout: workout, metricSeries: metricSeries, distanceUnitPreference: distanceUnitPreference
        )
    }

    private var longSplits: WorkoutSplitsPresentation? {
        WorkoutDetailChartPresentations.splits(
            workout: workout, splitData: splitData, distanceUnitPreference: distanceUnitPreference
        )
    }

    private var longElevation: WorkoutElevationLinePresentation? {
        WorkoutDetailChartPresentations.elevation(
            workout: workout,
            profile: route?.elevationProfile ?? [],
            distanceUnitPreference: distanceUnitPreference
        )
    }

    private var longCadence: WorkoutBucketedSeriesPresentation? {
        WorkoutDetailChartPresentations.cadence(
            workout: workout, metricSeries: metricSeries, distanceUnitPreference: distanceUnitPreference
        )
    }

    private var longPower: WorkoutBucketedSeriesPresentation? {
        WorkoutDetailChartPresentations.power(workout: workout, metricSeries: metricSeries)
    }

    private var longStrideLength: WorkoutBucketedSeriesPresentation? {
        WorkoutDetailChartPresentations.strideLength(
            workout: workout, metricSeries: metricSeries, distanceUnitPreference: distanceUnitPreference
        )
    }

    private var longGroundContact: WorkoutBucketedSeriesPresentation? {
        WorkoutDetailChartPresentations.groundContact(
            workout: workout, metricSeries: metricSeries, distanceUnitPreference: distanceUnitPreference
        )
    }

    private var longVerticalOscillation: WorkoutBucketedSeriesPresentation? {
        WorkoutDetailChartPresentations.verticalOscillation(
            workout: workout, metricSeries: metricSeries, distanceUnitPreference: distanceUnitPreference
        )
    }

    /// The long image, preview and export alike. The chip pick narrows both the tiles
    /// and — through the pure section policy — which charts draw.
    private func longCardView() -> BodyWorkoutShareLongCardView {
        let ids = activeLongMetricIDs
        let heartRateSamples = presentation.heartRateSamples
        let paceOrSpeed = longPaceOrSpeed
        let splits = longSplits
        let elevation = longElevation
        let cadence = longCadence
        let power = longPower
        let strideLength = longStrideLength
        let groundContact = longGroundContact
        let verticalOscillation = longVerticalOscillation
        let sections = WorkoutShareLongImageSections.sections(
            available: availableMetricOptions,
            selectedIDs: ids,
            data: WorkoutShareLongImageSections.Availability(
                heartRate: !heartRateSamples.isEmpty,
                pace: paceOrSpeed != nil,
                splits: splits != nil,
                elevation: elevation != nil,
                cadence: cadence != nil,
                power: power != nil,
                strideLength: strideLength != nil,
                groundContact: groundContact != nil,
                verticalOscillation: verticalOscillation != nil
            )
        )
        return BodyWorkoutShareLongCardView(
            presentation: presentation,
            // Pool order, and by tile rather than by `WorkoutShareMetric`, so the
            // comparison badges survive. `distance`/`time` have no Details tile of
            // their own — the header already carries both.
            tiles: ids.compactMap { id in
                longTilePool.first { WorkoutShareMetricOption.key(for: $0.kind) == id }
            },
            routePoints: isRouteHidden ? nil : routePoints,
            route3D: isRouteHidden ? nil : route3D,
            dimension: activeDimension,
            // The glyph only ever stands in for a workout that has no trace at all —
            // the same rule the card follows, so hiding a route doesn't put a symbol
            // where the route was.
            iconHidden: isIconHidden || hasRoute,
            locality: route?.locality,
            type: workout.type,
            preset: activeLongPreset,
            fontDesign: storedFontChoice.design,
            routeColor: storedRouteColorChoice.color(tint: workout.type.color),
            sections: sections,
            heartRateSamples: heartRateSamples,
            maxHeartRate: maxHeartRate ?? workout.maximumHeartRateBeatsPerMinute,
            paceOrSpeed: paceOrSpeed,
            splits: splits,
            elevation: elevation,
            cadence: cadence,
            power: power,
            strideLength: strideLength,
            groundContact: groundContact,
            verticalOscillation: verticalOscillation,
            attribution: activeAttribution
        )
    }

    /// Drag and pinch as one composite gesture, driving whichever transform the current
    /// step owns. `minimumDistance: 0` is what makes it track from the first point of
    /// travel, and the single `.updating`/`.onEnded` pair lives on the composite rather
    /// than on either half: a per-half `onEnded` fires while the composite's
    /// `@GestureState` is still live, double-applying the delta as soon as one finger
    /// lifts before the other. Both pinches are centre-anchored.
    private func adjustGesture(previewScale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .simultaneously(with: MagnifyGesture())
            .updating($inFlightGesture) { value, state, _ in
                state = Self.infoGesture(for: value, previewScale: previewScale)
            }
            .onEnded { value in
                let gesture = Self.infoGesture(for: value, previewScale: previewScale)
                switch photoStep {
                case .photo:
                    photoTransform = Self.merged(photoTransform, with: gesture)
                        .clamped(imageSize: activeMediaSize, cardSize: cardSize)
                case .layout:
                    committedInfoTransform = Self.merged(committedInfoTransform, with: gesture)
                        .clamped(cardSize: cardSize)
                }
            }
    }

    /// Puts the current step's transform back to its default slot.
    private func resetActiveTransform() {
        switch photoStep {
        case .photo: photoTransform = .identity
        case .layout: committedInfoTransform = .identity
        }
    }

    /// The preview draws the card scaled to fit its width, so a finger's travel in
    /// preview points divides back into card points before it moves anything.
    private static func infoGesture(
        for value: SimultaneousGesture<DragGesture, MagnifyGesture>.Value,
        previewScale: CGFloat
    ) -> WorkoutShareInfoGesture {
        let translation = value.first?.translation ?? .zero
        let divisor = previewScale.isFinite && previewScale > 0 ? previewScale : 1
        return WorkoutShareInfoGesture(
            translation: CGSize(width: translation.width / divisor, height: translation.height / divisor),
            magnification: value.second?.magnification ?? 1
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backdrop

                // Story-composer layering: the card fills the page and the rail floats
                // over its trailing edge. No ScrollView — the preview has to fit the
                // cover's height, and a scroll view's unbounded height would let the
                // card size off the width alone and run off the bottom.
                // The strip under the card — the metrics chips, or the media adjust
                // steps — takes its room from the preview: a VStack lets the card
                // shrink to fit above it rather than the strip covering the card's own
                // bottom edge. Metrics wins while its tray is open; closing it brings
                // the step chips back.
                VStack(spacing: 12) {
                    if isLongMode {
                        longPreview
                    } else {
                        cardPreview
                    }
                    if expandedOption == .metrics {
                        metricsTray
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if expandedOption == .profile, profileAvatarImage == nil || profileDisplayName == nil {
                        Text("Add a photo and name in Settings › Profile to show them on the card.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if isMediaMode, !isLongMode {
                        mediaAdjustTray
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(20)
                // Media mode is entered from `replaceMedia`'s async load, which carries
                // no transaction of its own, so the strip's arrival needs an explicit
                // animation to slide in rather than pop.
                .animation(reduceMotion ? nil : .snappy, value: isMediaMode)

                // The reader is only here for the tray's width budget; it draws nothing
                // itself, so the empty area around the rail stays untouchable.
                GeometryReader { proxy in
                    optionRail(availableWidth: proxy.size.width)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                }

            }
            // On the content stack rather than the sheet root: the root's top-center is
            // the toolbar's Share/v3 title, and this stack starts below the navigation
            // bar.
            .overlay(alignment: .top) {
                if isLoadingPhoto || isLoadingVideo {
                    BodySyncStatusBadgeLabel(icon: .spinner, text: "Importing media...")
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            // The import flags flip from an async load, which carries no transaction, so
            // the transition needs an animation of its own to run.
            .animation(reduceMotion ? nil : .snappy, value: isLoadingPhoto || isLoadingVideo)
            .photosPicker(isPresented: $isPickerPresented, selection: $photoItem, matching: .images)
            .photosPicker(isPresented: $isVideoPickerPresented, selection: $videoItem, matching: .videos)
            .sheet(isPresented: $showBodyProPaywall) {
                NavigationStack { BodyProView() }
            }
            // The title stays set for accessibility/back-button inheritance; the
            // principal item is what actually draws, so the version badge can sit beside it.
            .navigationTitle(Text("Share"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Text("Share")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("v3")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.blue.opacity(0.14), in: Capsule())
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        // Nothing downstream of a composite the user just walked away
                        // from: stop the encode before the sheet goes.
                        videoExportTask?.cancel()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .modifier(ShareToolbarIconChrome())
                    }
                    .accessibilityLabel(Text("Close"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await export() }
                    } label: {
                        Group {
                            if isRendering {
                                ProgressView()
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        .modifier(ShareToolbarIconChrome())
                    }
                    .disabled(isBusy)
                    .accessibilityLabel(Text("Share Workout"))
                }

                // Separates the two trailing actions into their own glass circles;
                // without it iOS 26 merges adjacent toolbar items into one capsule.
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await saveToPhotos() }
                    } label: {
                        Group {
                            if didSave {
                                Image(systemName: "checkmark")
                            } else if isSavingImage {
                                ProgressView()
                            } else {
                                Image(systemName: "square.and.arrow.down")
                            }
                        }
                        .modifier(ShareToolbarIconChrome())
                    }
                    .disabled(isBusy)
                    .accessibilityLabel(Text("Save to Photos"))
                }
            }
            .sheet(item: $payload) { payload in
                BodyShareActivityView(items: [payload.image]) { self.payload = nil }
            }
            // The exported file has to outlive the share sheet, so clearing the payload
            // is also what releases a scratch directory retired while it was up.
            .sheet(item: $videoPayload) { payload in
                BodyShareActivityView(items: [payload.url]) {
                    self.videoPayload = nil
                    removePendingScratch()
                }
            }
            .alert(Text("Couldn't Load Photo"), isPresented: $showPhotoLoadError) {
                Button("OK", role: .cancel) {}
            }
            .alert(Text("Couldn't Load Video"), isPresented: $showVideoLoadError) {
                Button("OK", role: .cancel) {}
            }
            .alert(Text("Couldn't Create Video"), isPresented: $showVideoExportError) {
                Button("OK", role: .cancel) {}
            }
            .alert(Text("Couldn't Save Video"), isPresented: $showVideoSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                if isPhotoAccessDenied {
                    Text("Body needs permission to add photos. Allow it in Settings › Body › Photos, then try again.")
                }
            }
            .alert(Text("Couldn't Load Map"), isPresented: $showMapLoadError) {
                Button("OK", role: .cancel) {}
            }
            .alert(Text("Couldn't Create Image"), isPresented: $showRenderError) {
                Button("OK", role: .cancel) {}
            }
            .alert(Text("Couldn't Save Image"), isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                if isPhotoAccessDenied {
                    Text("Body needs permission to add photos. Allow it in Settings › Body › Photos, then try again.")
                }
            }
            // Keyed off media mode itself, so every way in or out of it — a first pick, a
            // switch to a preset/map, a failed load, a lapsed entitlement — starts both
            // transforms from their default slot, at the first step.
            .onChange(of: isMediaMode) { _, _ in
                resetPhotoAdjustments()
            }
            // And off the media itself: replacing photo A with photo B (or with a clip)
            // never leaves media mode, so the mode key alone would keep A's framing
            // under B.
            .onChange(of: selectedMedia) { _, _ in
                resetPhotoAdjustments()
            }
            // A lapsed entitlement drops the clip back to the stored preset; the player
            // keeps its item so a restore resumes where it left off, but it must not go
            // on playing behind a background it no longer draws.
            // Long mode draws no video frames, so the clip must stop decoding behind a
            // preview that isn't showing it — the item is kept, so switching back
            // resumes where it left off.
            .onChange(of: isVideoPlaying) { _, isVideoActive in
                if isVideoActive {
                    previewPlayer?.play()
                } else {
                    previewPlayer?.pause()
                }
            }
            // A clamp is only valid for the card it was computed on: an offset that
            // parks the block near 16:9's edge would throw it off a 1:1 card entirely,
            // and the photo's overhang changes shape with the card too.
            .onChange(of: activeAspectRatio) { _, _ in
                resetPhotoAdjustments()
            }
            .task(id: photoItem) { await loadSelectedPhoto() }
            .task(id: videoItem) { await loadSelectedVideo() }
            // Seeds the decoded avatar once on appear; `cardView()` reads the `@State`
            // rather than decoding the JPEG itself, since it re-evaluates every gesture
            // frame.
            .task {
                profileAvatarImage = profileAvatarData.isEmpty ? nil : UIImage(data: profileAvatarData)
            }
            .onChange(of: profileAvatarData) { _, newValue in
                profileAvatarImage = newValue.isEmpty ? nil : UIImage(data: newValue)
            }
            // Everything the clip owns goes with the sheet: the encode nothing can
            // receive any more, the player, and every scratch directory still on disk.
            .onDisappear {
                videoExportTask?.cancel()
                videoExportTask = nil
                teardownPreviewPlayer()
                if let clip = selectedVideo {
                    pendingScratchIDs.append(clip.id)
                }
                for id in pendingScratchIDs {
                    WorkoutShareVideoClip.removeScratch(for: id)
                }
                pendingScratchIDs.removeAll()
            }
            // Opens on the map without waiting for a tap, and re-fires whenever the
            // snapshot on screen changes identity — so a Pro lapse (3D → 2D, or a
            // landscape ratio → 9:16), a restore, or a new ratio pick loads the newly
            // active snapshot on its own.
            .task(id: MapLoadKey(
                isMapActive: activeSelection == .map,
                dimension: activeDimension,
                aspectRatio: activeAspectRatio
            )) {
                let key = activeMapKey
                guard activeSelection == .map,
                      mapSnapshots[key] == nil,
                      !loadingMapKeys.contains(key),
                      !failedMapKeys.contains(key) else { return }
                await loadMapSnapshot(key: key, isUserInitiated: false)
            }
        }
    }

    @ViewBuilder
    private var backdrop: some View {
        // Pre-iOS-26 has no Liquid Glass, so use an opaque base behind the tinted gradient.
        if #unavailable(iOS 26.0) {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        }
        LinearGradient(
            colors: [workout.type.color.opacity(0.45), Color.black],
            startPoint: .top,
            endPoint: UnitPoint(x: 0.5, y: 0.5)
        )
        .ignoresSafeArea()
    }

    private var cardPreview: some View {
        // A clear box with the card's own aspect ratio establishes the layout size, and
        // `.fit` inside a max-size container means it fits *both* dimensions — so a
        // landscape card letterboxes in the middle instead of running off the bottom,
        // and the width- and height-derived scales coincide. That's what makes the one
        // `previewScale` below exact on every ratio.
        Color.clear
            .aspectRatio(cardSize.width / cardSize.height, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    let previewScale = proxy.size.width / cardSize.width
                    // Top-leading, not centered: in photo mode the gesture layer grows
                    // this stack to the proxy size, and centering would inset the fixed
                    // card before the top-leading scale — on an iPad-width preview that
                    // shows as blank space plus a clipped right/bottom edge.
                    ZStack(alignment: .topLeading) {
                        // Clip and card in one card-sized container, scaled *once*: two
                        // `.scaleEffect(previewScale)`s — one per layer — would let a
                        // rounding difference drift the overlay off the frames it's
                        // supposed to be pinned to.
                        ZStack(alignment: .topLeading) {
                            if activeSelection == .video, let clip = selectedVideo {
                                // The same chain the card gives a photo: fill, then
                                // zoom about the centre, then offset, then clip — the
                                // overhang has to survive until after the transform,
                                // because the clamp lets the pan use exactly that much.
                                // The layer is sized to the fill, not the card: an
                                // AVPlayerLayer clips to its bounds, so a card-sized
                                // layer would crop the overhang away before the pan.
                                let fill = WorkoutShareVideoComposer.fillSize(orientedSize: clip.orientedSize, in: cardSize)
                                BodyWorkoutShareVideoPreview(player: previewPlayer)
                                    .frame(width: fill.width, height: fill.height)
                                    .frame(width: cardSize.width, height: cardSize.height)
                                    .scaleEffect(activePhotoTransform.scale, anchor: .center)
                                    .offset(activePhotoTransform.offset)
                                    .frame(width: cardSize.width, height: cardSize.height)
                                    .clipped()
                            }

                            cardView()
                                .frame(width: cardSize.width, height: cardSize.height)
                                .environment(\.colorScheme, activeInk == .dark ? .light : .dark)
                        }
                        .frame(width: cardSize.width, height: cardSize.height)
                        .scaleEffect(previewScale, anchor: .topLeading)

                        if isMediaMode {
                            // An unscaled layer above the card: the gesture has to report
                            // translations in preview points for the ÷ previewScale above
                            // to be right on iPad, where the preview isn't ~1:1. The
                            // double tap goes on simultaneously — a zero-distance drag
                            // swallows taps otherwise.
                            Color.clear
                                .contentShape(Rectangle())
                                .highPriorityGesture(adjustGesture(previewScale: previewScale))
                                .simultaneousGesture(
                                    TapGesture(count: 2).onEnded {
                                        withAnimation { resetActiveTransform() }
                                    }
                                )
                                // Tapping the card also dismisses an open tray. It has
                                // to ride along simultaneously here: the drag and
                                // double-tap above own this layer, and the outer
                                // `onTapGesture` never sees a touch in photo mode.
                                .simultaneousGesture(
                                    TapGesture().onEnded { closeTray() }
                                )
                                // VoiceOver's double tap is its own activation gesture,
                                // so the reset needs a named action of its own — named
                                // for whichever thing this step actually moves.
                                .accessibilityAction(
                                    named: photoStep == .layout
                                    ? Text("Reset Layout")
                                    : (activeSelection == .video ? Text("Reset Video") : Text("Reset Photo"))
                                ) {
                                    resetActiveTransform()
                                }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Outside media mode nothing else wants a tap on the card, so this only
            // ever means "put the open tray away".
            .onTapGesture { closeTray() }
            // Nothing decodes while the preview is off screen (the paywall or the share
            // sheet covering it, the sheet going away); it picks back up on return.
            .onDisappear { previewPlayer?.pause() }
            .onAppear {
                if isVideoPlaying { previewPlayer?.play() }
            }
    }

    /// Whether the preview should actually be running the clip: a video background, and
    /// a card preview that draws it.
    private var isVideoPlaying: Bool { activeSelection == .video && !isLongMode }

    /// The long image, fitted to the preview's width and scrollable — it's taller than
    /// any screen by design. No gestures beyond the scroll and the tray dismissal: there
    /// is no backdrop to pan and no info block to move.
    private var longPreview: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width > 0 ? proxy.size.width / BodyWorkoutShareLongCardView.width : 1
            ScrollView(.vertical, showsIndicators: false) {
                longCardView()
                    .frame(width: BodyWorkoutShareLongCardView.width)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.colorScheme, activeLongPreset.ink == .dark ? .light : .dark)
                    // The scaled card doesn't report its scaled height (scaleEffect is a
                    // draw-time transform), so the natural height is measured here and
                    // the container below is sized to `height × scale` — otherwise the
                    // scroll view would offer a full unscaled card's worth of empty room.
                    .background(
                        GeometryReader { inner in
                            Color.clear.preference(key: LongCardHeightKey.self, value: inner.size.height)
                        }
                    )
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: proxy.size.width, height: longCardHeight * scale, alignment: .topLeading)
            }
            .onPreferenceChange(LongCardHeightKey.self) { height in
                longCardHeight = height
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .onTapGesture { closeTray() }
    }

    private func closeTray() {
        guard expandedOption != nil else { return }
        withAnimation(.snappy) { expandedOption = nil }
    }

    /// Which of the two adjust steps the gestures drive, in the strip under the card —
    /// the same place, and the same chip styling, as the metrics tray, so the media
    /// steps read as one more pick rather than a modal control over the photo.
    private var mediaAdjustTray: some View {
        let isVideo = activeSelection == .video
        return VStack(alignment: .center, spacing: 6) {
            HStack(spacing: 8) {
                // The first step is named for whatever it moves, so the chip and the
                // hint below it can't disagree about what's behind the card.
                mediaStepChip(.photo, label: isVideo ? Text("Video") : Text("Photo"))
                    .accessibilityHint(Text("Adjust the media, then choose Layout to move the workout info."))
                mediaStepChip(.layout, label: Text("Layout"))
            }

            Group {
                if photoStep != .photo {
                    Text("Drag to move. Pinch to resize. Double-tap to reset.")
                } else if isVideo {
                    Text("Drag to move the video. Pinch to zoom. Double-tap to reset.")
                } else {
                    Text("Drag to move the photo. Pinch to zoom. Double-tap to reset.")
                }
            }
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Full-width strip under the card, matching the metrics tray, so a tap beside
        // the chips still reaches nothing behind it.
        .frame(maxWidth: .infinity)
    }

    /// One adjust step, styled like `metricChip` so the two strips are one control set.
    private func mediaStepChip(_ step: PhotoAdjustStep, label: Text) -> some View {
        let isSelected = photoStep == step
        return Button {
            withAnimation { photoStep = step }
        } label: {
            HStack(spacing: 4) {
                if isSelected {
                    // The `.isSelected` trait below already says this to VoiceOver.
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .accessibilityHidden(true)
                }

                label
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(isSelected ? 0.28 : 0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private static let optionTileSize: CGFloat = 40
    private static let optionRowSpacing: CGFloat = 8
    /// Round rail buttons, big enough to be a comfortable target over the card.
    private static let railIconSize: CGFloat = 44
    private static let railPadding: CGFloat = 16
    /// Between a rail icon and its open tray.
    private static let railTrayGap: CGFloat = 12

    /// `textformat` rendered against an English locale: SF Symbols swaps that glyph for
    /// localized text ("格式" in Chinese), and the rail means font, not format.
    /// Sized here rather than by `.font`, which a `UIImage`-backed `Image` ignores.
    private static let fontRailIcon: Image? = UIImage(
        systemName: "textformat",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
            .applying(UIImage.SymbolConfiguration(locale: Locale(identifier: "en")))
    )
        .map { Image(uiImage: $0.withRenderingMode(.alwaysTemplate)) }

    /// The trailing icon rail (thumb side). Rows that don't apply to this workout are absent rather
    /// than disabled — a route-less card has no trace to colour, arrange, or lift.
    /// Everything here is free except the 3D tile and the non-9:16 ratios.
    private func optionRail(availableWidth: CGFloat) -> some View {
        // What's left of the page beside the rail, so an open tray can never run under
        // the trailing edge (it scrolls instead).
        let trayWidth = max(
            Self.optionTileSize,
            availableWidth - Self.railPadding * 2 - Self.railIconSize - Self.railTrayGap
        )
        // The map composites its own pace-coloured route into the snapshot, so neither
        // the trace colour nor the centered layout's arrangement changes anything there.
        let appliesToCardDrawnRoute = activeSelection != .map

        return VStack(alignment: .trailing, spacing: 22) {
            // The `textformat` symbol localizes itself — in Chinese it draws "格式"
            // (Format), naming the wrong thing — so this row pins the Latin "Aa" glyph.
            railRow(.font, icon: Self.fontRailIcon, label: Text("Font"), trayWidth: trayWidth) {
                optionTiles {
                    ForEach(WorkoutShareFontChoice.allCases) { choice in
                        fontTile(choice)
                    }
                }
            }

            if hasRoute {
                railRow(
                    .routeColor,
                    symbol: "scribble.variable",
                    label: Text("Route Color"),
                    trayWidth: trayWidth
                ) {
                    optionTiles {
                        ForEach(WorkoutShareRouteColorChoice.allCases) { choice in
                            routeColorTile(choice)
                        }
                    }
                }
                .opacity(appliesToCardDrawnRoute ? 1 : 0.4)
                .disabled(!appliesToCardDrawnRoute)
                .accessibilityHint(
                    appliesToCardDrawnRoute
                    ? Text(verbatim: "")
                    : Text("Route color doesn't apply to the Map background.")
                )
            }

            if hasRoute {
                railRow(.dimension, symbol: "move.3d", label: Text("Route Style"), trayWidth: trayWidth) {
                    dimensionTray
                }
            }

            // A route-less card has no trace to style, but it does have the type glyph
            // to hide — reusing `.dimension`'s rail slot since the two rows never both
            // apply to the same workout.
            if !hasRoute {
                railRow(.dimension, symbol: "figure.run", label: Text("Icon"), trayWidth: trayWidth) {
                    iconTray
                }
            }

            // Pro-only — locked rather than hidden, so a free user still
            // discovers the card can show something other than the automatic pick. Its
            // chips don't slide out beside the icon like the other trays: a rich workout
            // offers a dozen names, which would run straight under the card's own
            // metrics, so they take the strip below the preview instead.
            railRow(
                .metrics,
                symbol: "list.bullet.rectangle.portrait",
                label: Text("Metrics"),
                trayWidth: trayWidth,
                isLocked: !isProUnlocked,
                inlineTray: false
            ) {
                EmptyView()
            }

            // Always present and free — no lock, not gated on `hasRoute`: attribution
            // is a watermark addition, not a route-drawing option.
            railRow(.profile, symbol: "at", label: Text("Profile"), trayWidth: trayWidth) {
                profileTray
            }

            railRow(
                .background,
                symbol: "photo.on.rectangle",
                label: Text("Background"),
                trayWidth: trayWidth
            ) {
                backgroundTray
            }

            railRow(.ratio, symbol: "aspectratio", label: Text("Ratio"), trayWidth: trayWidth) {
                optionTiles {
                    ForEach(WorkoutShareAspectRatio.allCases) { ratio in
                        ratioTile(ratio)
                    }
                    // A sixth tile beside the ratios, not a sixth ratio: the long image
                    // is its own output style, with no fixed shape to pick.
                    longImageTile
                }
            }

            // Only a landscape card with a trace has two halves to split — and the long
            // image has no halves at all.
            if activeAspectRatio.isLandscape, hasRoute, !isLongMode {
                railRow(
                    .arrange,
                    symbol: "rectangle.split.2x1",
                    label: Text("Arrange"),
                    trayWidth: trayWidth
                ) {
                    optionTiles {
                        ForEach(WorkoutShareLandscapeArrangement.allCases) { arrangement in
                            arrangementTile(arrangement)
                        }
                    }
                }
                .opacity(appliesToCardDrawnRoute ? 1 : 0.4)
                .disabled(!appliesToCardDrawnRoute)
                .accessibilityHint(
                    appliesToCardDrawnRoute
                    ? Text(verbatim: "")
                    : Text("Layout doesn't apply to the Map background.")
                )
            }
        }
        .padding(.trailing, Self.railPadding)
        // A Pro lapse while the tray is open would leave the chips on screen editing a
        // pick the card no longer honours, so put the tray away with the entitlement.
        .onChange(of: isProUnlocked) {
            if !isProUnlocked, expandedOption == .metrics { closeTray() }
        }
    }

    /// One rail icon plus, when it's the open one, its tray sliding out to its left —
    /// the tray leads and the icon trails, so the icon column stays pinned to the edge.
    ///
    /// A locked row never opens its tray: the icon carries the Pro badge and its tap is
    /// the paywall, so a free user sees the option exists without reaching controls that
    /// wouldn't change the card.
    private func railRow<Content: View>(
        _ option: RailOption,
        symbol: String? = nil,
        icon: Image? = nil,
        label: Text,
        trayWidth: CGFloat,
        isLocked: Bool = false,
        inlineTray: Bool = true,
        @ViewBuilder tray: () -> Content
    ) -> some View {
        let isOpen = expandedOption == option
        return HStack(spacing: Self.railTrayGap) {
            if isOpen, inlineTray {
                tray()
                    .frame(maxWidth: trayWidth, alignment: .trailing)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            Button {
                guard !isLocked else {
                    closeTray()
                    showBodyProPaywall = true
                    return
                }
                withAnimation(.snappy) { expandedOption = isOpen ? nil : option }
            } label: {
                (icon ?? Image(systemName: symbol ?? ""))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: Self.railIconSize, height: Self.railIconSize)
                    .background(Color.black.opacity(0.35), in: Circle())
                    // Ringed while open, so the tray beside it reads as its content.
                    .overlay {
                        Circle().strokeBorder(
                            Color.white.opacity(isOpen ? 0.9 : 0.25),
                            lineWidth: isOpen ? 2 : 1
                        )
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if isLocked {
                            lockBadge
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(isLocked ? Text("Requires Body Pro") : Text(verbatim: ""))
        }
    }

    /// Avatar, nickname, and the dash between them and the wordmark, as three
    /// independent toggles rather than a radio pair — any combination can be on. No tap
    /// closes the tray, matching the metric chips: flipping one and then checking the
    /// next shouldn't require reopening.
    private var profileTray: some View {
        optionTiles {
            avatarTile
            nicknameTile
            separatorTile
        }
    }

    private var avatarTile: some View {
        let isAvailable = profileAvatarImage != nil
        let isSelected = isAvatarShown
        return Button {
            storedAvatarVisibility = isSelected
                ? WorkoutShareAvatarVisibility.hidden.rawValue
                : WorkoutShareAvatarVisibility.shown.rawValue
        } label: {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Self.optionTileSize, height: Self.optionTileSize)
                .background(Color.white.opacity(0.1), in: Circle())
                .overlay { selectionRing(isSelected: isSelected) }
        }
        .buttonStyle(.plain)
        .opacity(isAvailable ? 1 : 0.4)
        .disabled(!isAvailable)
        .accessibilityLabel(Text("Show Avatar"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(
            isAvailable ? Text(verbatim: "") : Text("Add it in Settings › Profile first.")
        )
    }

    private var nicknameTile: some View {
        let isAvailable = profileDisplayName != nil
        let isSelected = isNicknameShown
        return Button {
            storedNicknameVisibility = isSelected
                ? WorkoutShareNicknameVisibility.hidden.rawValue
                : WorkoutShareNicknameVisibility.shown.rawValue
        } label: {
            Image(systemName: "at")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Self.optionTileSize, height: Self.optionTileSize)
                .background(Color.white.opacity(0.1), in: Circle())
                .overlay { selectionRing(isSelected: isSelected) }
        }
        .buttonStyle(.plain)
        .opacity(isAvailable ? 1 : 0.4)
        .disabled(!isAvailable)
        .accessibilityLabel(Text("Show Nickname"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(
            isAvailable ? Text(verbatim: "") : Text("Add it in Settings › Profile first.")
        )
    }

    /// The dash between the wordmark and the attribution. Inert until something is
    /// actually shown beside the wordmark — with the attribution empty the card draws
    /// no separator whatever this toggle says, so offering it live would do nothing.
    private var separatorTile: some View {
        let isAvailable = !activeAttribution.isEmpty
        let isSelected = isSeparatorShown
        return Button {
            storedSeparatorVisibility = isSelected
                ? WorkoutShareSeparatorVisibility.hidden.rawValue
                : WorkoutShareSeparatorVisibility.shown.rawValue
        } label: {
            Image(systemName: "minus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Self.optionTileSize, height: Self.optionTileSize)
                .background(Color.white.opacity(0.1), in: Circle())
                .overlay { selectionRing(isSelected: isSelected) }
        }
        .buttonStyle(.plain)
        .opacity(isAvailable ? 1 : 0.4)
        .disabled(!isAvailable)
        .accessibilityLabel(Text("Show Separator"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(
            isAvailable ? Text(verbatim: "") : Text("Show your avatar or nickname first.")
        )
    }

    /// Horizontal scroller shared by every tray — seven route colours don't fit beside
    /// the rail on a small phone, and a clipped row would hide options entirely. The
    /// trailing anchor keeps a short row of tiles hugging its icon (a scroll view
    /// otherwise pins content to the leading edge, leaving a gap beside the rail) and
    /// opens a long row on its last tiles, next to the icon that opened it. The Metrics
    /// tray overrides the anchor to `.leading`: its chips are the pool in card order, so
    /// a long row has to open on the first metric rather than the last.
    /// Width of the soft edge the scroller fades under — both the mask gradient and the
    /// content inset that keeps resting tiles clear of it share this number.
    private static let optionTilesFade: CGFloat = 16

    private func optionTiles<Content: View>(
        anchor: UnitPoint = .trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        BodyOptionTileScroller(
            anchor: anchor,
            fade: Self.optionTilesFade,
            spacing: Self.optionRowSpacing
        ) {
            content()
        }
    }

    /// The backdrop tiles. In long mode only the gradient presets apply — the long
    /// image always paints one — so the map/photo/video tiles are dimmed and inert with
    /// a line saying why, rather than silently doing nothing when tapped.
    private var backgroundTray: some View {
        VStack(alignment: .trailing, spacing: 6) {
            optionTiles {
                ForEach(BodyWorkoutSharePreset.allCases) { preset in
                    presetSwatch(preset)
                }
                // Nothing to snapshot without a route, so the tile isn't offered.
                if hasRoute {
                    mapTile()
                        .opacity(isLongMode ? 0.4 : 1)
                        .disabled(isLongMode)
                }
                photoTile()
                    .opacity(isLongMode ? 0.4 : 1)
                    .disabled(isLongMode)
                videoTile()
                    .opacity(isLongMode ? 0.4 : 1)
                    .disabled(isLongMode)
            }

            if isLongMode {
                Text("The long image uses a gradient background.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Which metrics the card shows. Chips rather than round tiles: the thing being
    /// picked is a name, not a specimen or a swatch, and the pool can run past a dozen
    /// entries on a rich workout.
    private var metricsTray: some View {
        VStack(alignment: .center, spacing: 6) {
            optionTiles(anchor: .leading) {
                ForEach(availableMetricOptions) { option in
                    metricChip(option)
                }
            }

            // The long image has no five-metric ceiling, so its caption says what the
            // chips do rather than quoting bounds that don't apply.
            Group {
                if isLongMode {
                    Text("Pick the metrics for the long image.")
                } else {
                    Text("Pick 1 to 5 metrics.")
                }
            }
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        // Full-width strip under the card, so the scroller isn't sized by the rail's
        // tray budget and a tap between chips still reaches nothing behind it.
        .frame(maxWidth: .infinity)
    }

    /// One pickable metric. Unlike every other tray, a tap here doesn't close the tray:
    /// picking five metrics is five taps, and re-opening between each would make the
    /// bounds impossible to feel.
    private func metricChip(_ option: WorkoutShareMetricOption) -> some View {
        let isLong = isLongMode
        let ids = isLong ? activeLongMetricIDs : activeMetricIDs
        let isSelected = ids.contains(option.id)
        // The long image has no ceiling to dim against.
        let isAtMaximum = !isLong && ids.count >= WorkoutShareMetricSelection.maximumCount
        let isLastSelected = isSelected && ids.count == 1
        return Button {
            let next = isLong
                ? WorkoutShareMetricSelection.togglingLong(option.id, in: ids, available: availableMetricOptions)
                : WorkoutShareMetricSelection.toggling(option.id, in: ids, available: availableMetricOptions)
            guard next != ids else { return }
            if isLong {
                storedLongMetricSelections = WorkoutShareMetricSelection.storing(
                    next,
                    for: workout.type,
                    into: storedLongMetricSelections
                )
            } else {
                storedMetricSelections = WorkoutShareMetricSelection.storing(
                    next,
                    for: workout.type,
                    into: storedMetricSelections
                )
            }
        } label: {
            HStack(spacing: 4) {
                if isSelected {
                    // The `.isSelected` trait below already says this to VoiceOver.
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .accessibilityHidden(true)
                }

                Text(option.centeredMetric.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(isSelected ? 0.28 : 0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        // Dimmed rather than hidden at the cap, so the user can see what they'd have to
        // give up to add one more.
        .opacity(!isSelected && isAtMaximum ? 0.4 : 1)
        .disabled(!isSelected && isAtMaximum)
        // The tile's own wording plus what it currently reads, so VoiceOver users pick
        // by value the way sighted users do.
        .accessibilityLabel(Text(verbatim: "\(option.tileTitle), \(option.value)"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(
            isLastSelected ? Text("At least one metric stays on the card.") : Text(verbatim: "")
        )
    }

    /// Ring-only selection, no checkmark: the point of the tile is the "Aa" specimen,
    /// and a glyph on top of it would hide the very thing being picked.
    private func fontTile(_ choice: WorkoutShareFontChoice) -> some View {
        let isSelected = storedFontChoice == choice
        return Button {
            closeTray()
            storedFont = choice.rawValue
        } label: {
            Text(verbatim: "Aa")
                .font(.system(size: 17, weight: .semibold, design: choice.design))
                .foregroundStyle(.white)
                .frame(width: Self.optionTileSize, height: Self.optionTileSize)
                .background(Color.white.opacity(0.1), in: Circle())
                .overlay { selectionRing(isSelected: isSelected) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.localizedName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// The card's shape. The outline inside the circle is the ratio itself, drawn at a
    /// fixed 20 pt long side so the five ratio tiles — and the Long Image tile that
    /// follows them — read as one family of shapes.
    private func ratioTile(_ ratio: WorkoutShareAspectRatio) -> some View {
        // No ratio is the active shape while the long image is: it has none.
        let isSelected = activeAspectRatio == ratio && !isLongMode
        let size = ratio.cardSize
        let longSide: CGFloat = 20
        let outlineWidth = size.width >= size.height ? longSide : longSide * size.width / size.height
        let outlineHeight = size.height >= size.width ? longSide : longSide * size.height / size.width
        let isLocked = ratio.isProGated && !isProUnlocked
        return Button {
            closeTray()
            guard !isLocked else {
                showBodyProPaywall = true
                return
            }
            storedAspectRatio = ratio.rawValue
            // Picking a shape is asking for the card back.
            storedOutputStyle = WorkoutShareOutputStyle.card.rawValue
        } label: {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(.white, lineWidth: 1.5)
                .frame(width: outlineWidth, height: outlineHeight)
                .frame(width: Self.optionTileSize, height: Self.optionTileSize)
                .background(Color.white.opacity(0.1), in: Circle())
                .overlay { selectionRing(isSelected: isSelected) }
                .overlay(alignment: .bottomTrailing) {
                    if isLocked {
                        lockBadge
                    }
                }
        }
        .buttonStyle(.plain)
        // The tile's own "16:9" is numerals; VoiceOver gets the spelled-out shape.
        .accessibilityLabel(ratio.localizedName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// The sixth tile in the Ratio tray: the whole detail page as one tall picture.
    /// A taller, narrower outline than any ratio offers, so it reads as "longer than
    /// these" rather than as another shape. Pro — locked rather than hidden, like the
    /// non-9:16 ratios beside it.
    private var longImageTile: some View {
        let isSelected = isLongMode
        let isLocked = !isProUnlocked
        return Button {
            closeTray()
            guard !isLocked else {
                showBodyProPaywall = true
                return
            }
            storedOutputStyle = WorkoutShareOutputStyle.longImage.rawValue
        } label: {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(.white, lineWidth: 1.5)
                .frame(width: 11, height: 26)
                .frame(width: Self.optionTileSize, height: Self.optionTileSize)
                .background(Color.white.opacity(0.1), in: Circle())
                .overlay { selectionRing(isSelected: isSelected) }
                .overlay(alignment: .bottomTrailing) {
                    if isLocked {
                        lockBadge
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Long Image"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// How a landscape card splits route from metrics. Free — the ratio that reveals
    /// this row is what carries the Pro gate.
    private func arrangementTile(_ arrangement: WorkoutShareLandscapeArrangement) -> some View {
        let isSelected = activeArrangement == arrangement
        return Button {
            closeTray()
            storedArrangement = arrangement.rawValue
        } label: {
            Image(systemName: arrangement.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Self.optionTileSize, height: Self.optionTileSize)
                .background(Color.white.opacity(0.1), in: Circle())
                .overlay { selectionRing(isSelected: isSelected) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(arrangement.localizedName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Flat trace or elevation ribbon, plus the reason the ribbon can be unavailable.
    /// Only the 3D tile is dimmed for a route without altitude — 2D stays tappable, so
    /// a user who wandered in here can still get back out.
    private var dimensionTray: some View {
        VStack(alignment: .trailing, spacing: 6) {
            optionTiles {
                hideRouteTile
                dimensionTile(.twoD)
                dimensionTile(.threeD)
            }

            if !isThreeDAvailable {
                Text("3D needs a route with elevation data.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func dimensionTile(_ dimension: WorkoutShareRouteDimension) -> some View {
        // Keyed off the *resolved* dimension: a stored 3D that can't render (non-Pro, or
        // a flat route) shows 2D selected, because 2D is what the card is drawing.
        // A hidden trace (on a card-drawn background) selects neither: the Hide tile
        // holds the ring. The map keeps showing its dimension — it ignores hiding.
        let isSelected = activeDimension == dimension && !(isRouteHidden && activeSelection != .map)
        let isAvailable = dimension == .twoD || isThreeDAvailable
        let isLocked = dimension == .threeD && !isProUnlocked
        return Button {
            closeTray()
            guard !isLocked else {
                showBodyProPaywall = true
                return
            }
            storedDimension = dimension.rawValue
            // Picking a dimension is asking to see the trace again.
            storedRouteVisibility = WorkoutShareRouteVisibility.shown.rawValue
        } label: {
            Group {
                if dimension == .twoD {
                    Text("2D")
                } else {
                    Text("3D")
                }
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: Self.optionTileSize, height: Self.optionTileSize)
            .background(Color.white.opacity(0.1), in: Circle())
            .overlay { selectionRing(isSelected: isSelected) }
            .overlay(alignment: .bottomTrailing) {
                if isLocked {
                    lockBadge
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(isAvailable ? 1 : 0.4)
        .disabled(!isAvailable)
        .accessibilityLabel(dimension == .twoD ? Text("2D") : Text("3D"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(
            isAvailable ? Text(verbatim: "") : Text("3D needs a route with elevation data.")
        )
    }

    /// Metrics only, no trace. Disabled on the Map background: its route is baked into
    /// the snapshot, and a map framed to a route it doesn't show would be a map of
    /// nothing — the stored choice waits for a gradient or photo.
    private var hideRouteTile: some View {
        let appliesHere = activeSelection != .map
        let isSelected = isRouteHidden && appliesHere
        return Button {
            closeTray()
            storedRouteVisibility = WorkoutShareRouteVisibility.hidden.rawValue
        } label: {
            Image(systemName: "eye.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Self.optionTileSize, height: Self.optionTileSize)
                .background(Color.white.opacity(0.1), in: Circle())
                .overlay { selectionRing(isSelected: isSelected) }
        }
        .buttonStyle(.plain)
        .opacity(appliesHere ? 1 : 0.4)
        .disabled(!appliesHere)
        .accessibilityLabel(Text("Hide Route"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(
            appliesHere ? Text(verbatim: "") : Text("Hiding the route doesn't apply to the Map background.")
        )
    }

    /// Show/Hide, mirroring `hideRouteTile`'s shape for the route-less card's glyph.
    /// Free — no lock badge.
    private var iconTray: some View {
        optionTiles {
            showIconTile
            hideIconTile
        }
    }

    private var showIconTile: some View {
        let isSelected = !isIconHidden
        return Button {
            closeTray()
            storedIconVisibility = WorkoutShareIconVisibility.shown.rawValue
        } label: {
            Image(systemName: workout.type.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Self.optionTileSize, height: Self.optionTileSize)
                .background(Color.white.opacity(0.1), in: Circle())
                .overlay { selectionRing(isSelected: isSelected) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Show Icon"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var hideIconTile: some View {
        let isSelected = isIconHidden
        return Button {
            closeTray()
            storedIconVisibility = WorkoutShareIconVisibility.hidden.rawValue
        } label: {
            Image(systemName: "eye.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Self.optionTileSize, height: Self.optionTileSize)
                .background(Color.white.opacity(0.1), in: Circle())
                .overlay { selectionRing(isSelected: isSelected) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Hide Icon"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func routeColorTile(_ choice: WorkoutShareRouteColorChoice) -> some View {
        let isSelected = storedRouteColorChoice == choice
        return Button {
            closeTray()
            storedRouteColor = choice.rawValue
        } label: {
            Circle()
                .fill(choice.color(tint: workout.type.color))
                .frame(width: Self.optionTileSize, height: Self.optionTileSize)
                // Ring only, again: a checkmark would vanish on White and swamp Black.
                .overlay { selectionRing(isSelected: isSelected) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.localizedName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func selectionRing(isSelected: Bool, stroke: Color = .white) -> some View {
        Circle()
            .strokeBorder(
                stroke.opacity(isSelected ? 0.9 : 0.3),
                lineWidth: isSelected ? 2 : 1
            )
    }

    /// The Pro badge the 3D and non-9:16 tiles carry for a non-Pro user, and the photo
    /// tile always has.
    private var lockBadge: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(4)
            .background(Color.black.opacity(0.55), in: Circle())
    }

    private func presetSwatch(_ preset: BodyWorkoutSharePreset) -> some View {
        // In long mode the ring follows the gradient that actually paints — a stored
        // map resolves to Midnight there (the long image never draws a map, so a held
        // photo doesn't factor in) and must not leave the strip showing a selection
        // nothing renders.
        let isSelected = isLongMode ? activeLongPreset == preset : activeSelection == .preset(preset)
        return Button {
            closeTray()
            storedBackground = BodyWorkoutShareBackgroundChoice.preset(preset).rawValue
            // Also resets the picker items, so re-picking the same asset later re-fires
            // the `.task(id:)` load (an unchanged id would silently do nothing).
            replaceMedia(with: nil)
        } label: {
            Circle()
                .fill(preset.gradient(tint: workout.type.color))
                .frame(width: Self.optionTileSize, height: Self.optionTileSize)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(preset.ink == .dark ? .black : .white)
                    }
                }
                // Daylight's white circle needs its own edge — a white hairline would
                // be invisible on it, so this one stays dark and permanent, inside the
                // ring below rather than instead of it.
                .overlay {
                    if preset.ink == .dark {
                        Circle().strokeBorder(Color.black.opacity(0.15))
                    }
                }
                .overlay {
                    selectionRing(
                        isSelected: isSelected,
                        stroke: preset.ink == .dark ? Color.black.opacity(0.6) : .white
                    )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.localizedName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Free route-map background: a dark map snapshot with the pace-colored route
    /// composited in, generated once per dimension+ratio on first selection.
    private func mapTile() -> some View {
        let key = activeMapKey
        let isSelected = activeSelection == .map
        let snapshot = mapSnapshots[key]
        return Button {
            closeTray()
            replaceMedia(with: nil)
            storedBackground = BodyWorkoutShareBackgroundChoice.map.rawValue
            // Tapping Map is also how the user retries this snapshot after a failure.
            failedMapKeys.remove(key)
            if mapSnapshots[key] == nil, !loadingMapKeys.contains(key) {
                Task { await loadMapSnapshot(key: key, isUserInitiated: true) }
            }
        } label: {
            ZStack {
                if let snapshot {
                    Image(uiImage: snapshot)
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle().fill(Color.white.opacity(0.1))
                    Image(systemName: "map")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                if loadingMapKeys.contains(key) {
                    Circle().fill(Color.black.opacity(0.35))
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(width: Self.optionTileSize, height: Self.optionTileSize)
            .clipShape(Circle())
            .overlay { selectionRing(isSelected: isSelected) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Map"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func photoTile() -> some View {
        let isSelected = isPhotoActive
        return Button {
            closeTray()
            guard isProUnlocked else {
                showBodyProPaywall = true
                return
            }
            isPickerPresented = true
        } label: {
            ZStack {
                if let selectedPhoto {
                    Image(uiImage: selectedPhoto)
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle().fill(Color.white.opacity(0.1))
                    Image(systemName: "photo")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(width: Self.optionTileSize, height: Self.optionTileSize)
            .clipShape(Circle())
            .overlay { selectionRing(isSelected: isSelected) }
            .overlay(alignment: .bottomTrailing) {
                if !isProUnlocked {
                    lockBadge
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Your Photo"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// The user's own clip behind the card — Pro, session-only, and mutually exclusive
    /// with the photo. The thumbnail is the clip's own first frame, so the tile shows
    /// which video is loaded rather than a generic glyph.
    private func videoTile() -> some View {
        let isSelected = activeSelection == .video
        return Button {
            closeTray()
            guard isProUnlocked else {
                showBodyProPaywall = true
                return
            }
            isVideoPickerPresented = true
        } label: {
            ZStack {
                if let poster = selectedVideo?.poster {
                    Image(uiImage: poster)
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle().fill(Color.white.opacity(0.1))
                    Image(systemName: "video.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(width: Self.optionTileSize, height: Self.optionTileSize)
            .clipShape(Circle())
            .overlay { selectionRing(isSelected: isSelected) }
            .overlay(alignment: .bottomTrailing) {
                if !isProUnlocked {
                    lockBadge
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Your Video"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// The one way the backdrop changes. Every writer goes through here so the outgoing
    /// clip is always torn down in the one safe order — stop the player, drop the looper
    /// that keeps feeding it, empty the queue, release it, and only then delete the
    /// files it was reading — and so picking either kind of media clears the other.
    private func replaceMedia(with media: SelectedMedia?) {
        // A composite whose source is about to be replaced can only produce the wrong
        // file, and it holds the scratch directory open while it runs.
        videoExportTask?.cancel()
        videoExportTask = nil

        var incomingClipID: UUID?
        var isIncomingPhoto = false
        switch media {
        case .video(let clip): incomingClipID = clip.id
        case .photo: isIncomingPhoto = true
        case nil: break
        }

        if let outgoing = selectedVideo, outgoing.id != incomingClipID {
            teardownPreviewPlayer()
            retireScratch(outgoing.id)
        }

        selectedMedia = media
        // Re-picking the same asset has to re-fire its `.task(id:)`, so whichever
        // picker no longer owns the background forgets its item.
        if !isIncomingPhoto { photoItem = nil }
        if incomingClipID == nil { videoItem = nil }
    }

    private func teardownPreviewPlayer() {
        previewPlayer?.pause()
        previewLooper = nil
        previewPlayer?.removeAllItems()
        previewPlayer = nil
    }

    /// Muted and looping the exact range the export will cut, so the preview is a
    /// faithful rehearsal of the file.
    private func startPreviewPlayer(for clip: WorkoutShareVideoClip) {
        let player = AVQueuePlayer()
        player.isMuted = true
        previewLooper = AVPlayerLooper(
            player: player,
            templateItem: AVPlayerItem(asset: clip.asset),
            timeRange: clip.exportTimeRange
        )
        previewPlayer = player
        player.play()
    }

    /// Deletes a retired clip's files, unless the share sheet is still holding its
    /// exported URL or a save is writing it — then it waits for those to finish.
    private func retireScratch(_ id: UUID) {
        pendingScratchIDs.append(id)
        removePendingScratch()
    }

    private func removePendingScratch() {
        guard videoPayload == nil, !isSavingImage else { return }
        for id in pendingScratchIDs {
            WorkoutShareVideoClip.removeScratch(for: id)
        }
        pendingScratchIDs.removeAll()
    }

    /// Both photo transforms back to their defaults, at the first step.
    private func resetPhotoAdjustments() {
        committedInfoTransform = .identity
        photoTransform = .identity
        photoStep = .photo
    }

    /// Also busy while the *active* background is still loading — rendering then would
    /// silently rasterize the previous/preset background instead. Keyed on the active
    /// dimension's snapshot rather than on a loading flag: a Pro lapse or restore can
    /// make a dimension active whose load hasn't even started yet. A failed dimension
    /// flips `activeSelection` to Midnight, so this can't wedge.
    /// The long image never consults the map snapshot, so a stored `.map` must not
    /// leave Share and Save disabled there waiting for one.
    private var isBusy: Bool {
        isRendering || isSavingImage || isLoadingPhoto || isLoadingVideo
            || (!isLongMode && activeSelection == .map && activeMapSnapshot == nil)
    }

    /// What this tap produces. Read once and branched on in both `export()` and
    /// `saveToPhotos()` — including the photo-permission error copy — because forcing
    /// the background selection does *not* nil out a clip the user already picked, so
    /// "is there a video?" alone is the wrong question in long mode.
    private var activeOutput: WorkoutShareOutput {
        WorkoutShareBackgroundPolicy.resolvedOutput(
            style: activeOutputStyle,
            hasRenderableVideo: renderableVideo != nil
        )
    }

    @MainActor
    private func export() async {
        guard !isRendering else { return }

        // A video's composite is minutes of work in the worst case, so it runs as a
        // cancellable task Close can stop; both image paths are a single synchronous
        // rasterization and stay inline.
        switch activeOutput {
        case .video:
            guard let clip = renderableVideo else { return }
            isRendering = true
            let task = Task { @MainActor in
                defer { isRendering = false }
                do {
                    let url = try await composeVideo(clip: clip)
                    try Task.checkCancellation()
                    videoPayload = WorkoutShareVideoPayload(url: url, clipID: clip.id)
                } catch is CancellationError {
                    // The user left, or replaced the clip under it — nothing to say.
                } catch {
                    showVideoExportError = true
                }
            }
            videoExportTask = task
            await task.value
            if videoExportTask == task { videoExportTask = nil }

        case .cardImage, .longImage:
            isRendering = true
            defer { isRendering = false }

            if let image = renderShareImage() {
                payload = WorkoutSharePayload(image: image)
            } else {
                showRenderError = true
            }
        }
    }

    /// The card rendered once and held over every frame of the clip's exported range —
    /// the video half of what `renderCardImage()` is for a still.
    @MainActor
    private func composeVideo(clip: WorkoutShareVideoClip) async throws -> URL {
        guard let overlay = renderCardImage() else { throw ShareError.decodeFailed }
        return try await WorkoutShareVideoComposer.export(
            clip: clip,
            overlay: overlay,
            cardSize: cardSize,
            photoTransform: activePhotoTransform
        )
    }

    /// Writes the card to the photo library with add-only access — never full-library
    /// read — so the prompt matches what saving actually needs.
    @MainActor
    private func saveToPhotos() async {
        guard !isSavingImage else { return }
        let output = activeOutput
        // Keyed off what is actually being written, so a long image over a held clip
        // gets the image permission copy rather than the video's.
        let isVideo = output == .video
        isSavingImage = true
        defer {
            isSavingImage = false
            // A clip retired while this save was writing its file can go now.
            removePendingScratch()
        }

        switch await Self.requestAddOnlyPhotoAccess() {
        case .authorized, .limited:
            break
        default:
            isPhotoAccessDenied = true
            if isVideo { showVideoSaveError = true } else { showSaveError = true }
            return
        }

        if output == .video, let clip = renderableVideo {
            await saveVideoToPhotos(clip: clip)
            return
        }

        guard let image = renderShareImage() else {
            showRenderError = true
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAsset(from: image)
            }
        } catch {
            isPhotoAccessDenied = false
            showSaveError = true
            return
        }

        finishSave()
    }

    /// Composites, then writes the MP4 as a resource on a new asset — the file outlives
    /// the request (the share sheet may still want it), so it is never moved. Runs in
    /// `videoExportTask` so Close cancels the encode.
    @MainActor
    private func saveVideoToPhotos(clip: WorkoutShareVideoClip) async {
        let task = Task { @MainActor in
            do {
                let url = try await composeVideo(clip: clip)
                try Task.checkCancellation()
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetCreationRequest.forAsset()
                        .addResource(with: .video, fileURL: url, options: nil)
                }
                finishSave()
            } catch is CancellationError {
                // The user left, or replaced the clip under it — nothing to say.
            } catch {
                isPhotoAccessDenied = false
                showVideoSaveError = true
            }
        }
        videoExportTask = task
        await task.value
        if videoExportTask == task { videoExportTask = nil }
    }

    /// Confirmation lives on the button itself; hold it just long enough to read,
    /// then close the sheet — a successful save is this flow's natural end. On its
    /// own task so `defer` re-enables both buttons right away.
    @MainActor
    private func finishSave() {
        didSave = true
        Task {
            try? await Task.sleep(for: .seconds(1))
            dismiss()
        }
    }

    /// The still Save and Share hand on — whichever of the two the mode asks for.
    @MainActor
    private func renderShareImage() -> UIImage? {
        isLongMode ? renderLongImage() : renderCardImage()
    }

    /// How many pixels tall an exported long image may get. A twenty-split marathon is
    /// several thousand points tall, and 3× on top of that is a bitmap the photo library
    /// (and the share extension receiving it) would rather not see.
    private static let maximumLongOutputPixels: CGFloat = 12_000

    /// How far the long image may be upscaled: the card's 3× unless that would break the
    /// pixel budget, and `nil` — export refused, "Couldn't Create Image" shown — when
    /// even 1× would. Pure, so the rule can be read and tested without rasterizing
    /// anything.
    static func longExportScale(forHeight heightPoints: CGFloat) -> CGFloat? {
        guard heightPoints > 0, heightPoints.isFinite else { return nil }
        let scale = min(3, maximumLongOutputPixels / heightPoints)
        return scale >= 1 ? scale : nil
    }

    /// The long image: 360 pt wide, naturally tall. `ImageRenderer` has no
    /// `sizeThatFits`, so the height comes from a scale-1 pass — which is also the image
    /// itself when no upscaling is affordable. The scale then backs off from 3 so a very
    /// tall workout stays under `maximumLongOutputPixels`; a page so long that even 1×
    /// exceeds it renders nothing and falls into the "Couldn't Create Image" alert
    /// rather than allocating a bitmap that would take the app down.
    ///
    /// Reduce Motion is forced on for the same reason the colour scheme and type size
    /// are: the chart helpers read it, and an export must not depend on the device's
    /// accessibility settings.
    @MainActor
    private func renderLongImage() -> UIImage? {
        let renderer = ImageRenderer(
            content: longCardView()
                .frame(width: BodyWorkoutShareLongCardView.width)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.colorScheme, activeLongPreset.ink == .dark ? .light : .dark)
                .dynamicTypeSize(.large)
                // `accessibilityReduceMotion` is read-only in `EnvironmentValues`, so
                // the determinism it would buy is taken here instead: the chart cards
                // only read it to drop animations and numeric content transitions, and
                // this disables both regardless of the device's setting.
                .transaction { $0.disablesAnimations = true }
        )
        renderer.proposedSize = ProposedViewSize(width: BodyWorkoutShareLongCardView.width, height: nil)
        renderer.scale = 1

        guard let measured = renderer.uiImage else { return nil }
        guard let scale = Self.longExportScale(forHeight: measured.size.height) else { return nil }
        guard scale > 1 else { return measured }

        renderer.scale = scale
        return renderer.uiImage
    }

    /// The one rasterization path Save and Share share: the card at its chosen point
    /// size, 3× (1080 px on the short side), forced dark and at `.large` dynamic type so
    /// the exported image never picks up the device's appearance or text-size settings.
    @MainActor
    private func renderCardImage() -> UIImage? {
        let renderer = ImageRenderer(
            content: cardView()
                .frame(width: cardSize.width, height: cardSize.height)
                .environment(\.colorScheme, activeInk == .dark ? .light : .dark)
                .dynamicTypeSize(.large)
        )
        renderer.scale = 3
        return renderer.uiImage
    }

    /// `PHPhotoLibrary.requestAuthorization(for:handler:)` has no async form, so bridge
    /// the completion-based one.
    nonisolated private static func requestAddOnlyPhotoAccess() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Latest-wins, cancellable photo load. Decodes off the main actor and keeps only
    /// the downscaled `UIImage`; the source `Data` is released once the thumbnail is built.
    private func loadSelectedPhoto() async {
        guard let item = photoItem else { return }

        isLoadingPhoto = true
        defer {
            // `.task(id:)` cancels a superseded invocation but doesn't wait for it,
            // so a slow predecessor can outlive its successor's start. Only the
            // invocation that still owns the current selection may clear the flag
            // (photoItem == nil means the user switched to a preset/map — the
            // cancelled load is then the last owner and must release it).
            if photoItem == item || photoItem == nil {
                isLoadingPhoto = false
            }
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw ShareError.decodeFailed
            }
            let image = try await Task.detached(priority: .userInitiated) {
                try Self.downscaledImage(from: data, maxPixelSize: 2_400)
            }.value
            try Task.checkCancellation()
            // The photo is session-only and outranks the stored choice in
            // `activeSelection`, so it never writes `storedBackground` — dismissing or
            // failing a photo returns to whatever was persisted. Through `replaceMedia`
            // because a photo also displaces a held clip.
            replaceMedia(with: .photo(image))
        } catch is CancellationError {
            // A newer selection superseded this load; leave existing state untouched.
        } catch {
            // A failure only matters if this request is still the active selection —
            // a superseded load's error must not fire an alert over the new choice.
            guard photoItem == item else { return }
            // Keep any previously loaded photo as the active background — a failed
            // replacement shouldn't discard what the user already had. Clearing the
            // item lets them re-pick the same asset (task(id:) needs a change).
            photoItem = nil
            showPhotoLoadError = true
        }
    }

    /// Latest-wins, cancellable clip load, on the same discipline as the photo's. The
    /// transfer copies the asset into a scratch directory of its own (an iCloud clip
    /// can take a while to arrive), so every path that doesn't end up using it has to
    /// delete that directory again.
    private func loadSelectedVideo() async {
        guard let item = videoItem else { return }

        isLoadingVideo = true
        defer {
            // Same rule as the photo loader: only the invocation that still owns the
            // current selection may clear the flag.
            if videoItem == item || videoItem == nil {
                isLoadingVideo = false
            }
        }

        var scratchID: UUID?
        do {
            guard let transfer = try await item.loadTransferable(type: VideoFileTransfer.self) else {
                throw ShareError.decodeFailed
            }
            scratchID = transfer.id
            try Task.checkCancellation()
            let clip = try await WorkoutShareVideoClip.load(url: transfer.url)
            try Task.checkCancellation()
            // A newer pick landed while this one was inspecting: its files are ours to
            // clean up, and the winner's state must not be overwritten.
            guard videoItem == item else {
                WorkoutShareVideoClip.removeScratch(for: clip.id)
                return
            }
            replaceMedia(with: .video(clip))
            startPreviewPlayer(for: clip)
        } catch is CancellationError {
            if let scratchID { WorkoutShareVideoClip.removeScratch(for: scratchID) }
        } catch {
            if let scratchID { WorkoutShareVideoClip.removeScratch(for: scratchID) }
            // A superseded load's error must not fire an alert over the new choice.
            guard videoItem == item else { return }
            // Keep whatever background the user already had; clearing the item lets
            // them re-pick the same asset (task(id:) needs a change).
            videoItem = nil
            showVideoLoadError = true
        }
    }

    @MainActor
    private func loadMapSnapshot(key: MapSnapshotKey, isUserInitiated: Bool) async {
        // Before the flag, not after: a route-less sheet has no map to load, and
        // flipping the loading flag for a call that can't finish one would be enough
        // to leave Save/Share disabled.
        guard let route else { return }
        loadingMapKeys.insert(key)
        defer { loadingMapKeys.remove(key) }

        let image = await Self.mapBackground(
            for: route,
            tint: UIColor(workout.type.color),
            dimension: key.dimension,
            aspectRatio: key.aspectRatio
        )
        if let image {
            // Cache even if the user switched away meanwhile — re-selecting this
            // dimension/ratio then shows the snapshot instantly.
            mapSnapshots[key] = image
        } else if Task.isCancelled {
            // Not a failure: flipping the ratio A→B→A cancels A's in-flight load, and
            // recording that as a failure would leave A stuck on Midnight until the
            // user tapped Map again. The `.task(id:)` for the key now on screen is
            // already running and will fill it in.
        } else {
            // Read the selection before recording the failure: recording it is what
            // makes `activeSelection` fall back to Midnight.
            let isStillRequested = activeSelection == .map && activeMapKey == key
            // Recorded whatever the user is looking at now, so the opening task won't
            // retry a snapshot that just failed — the Map tile clears it to retry.
            failedMapKeys.insert(key)
            // Only alert while this snapshot is still what's on screen and the user
            // asked for it: a stale error over a tile they already left is noise, and
            // the sheet's own opening load must not alert on every unsnapshottable route.
            if isStillRequested, isUserInitiated {
                showMapLoadError = true
            }
        }
    }

    /// Full-card (the ratio's point size at 3×) dark map snapshot with the pace-colored
    /// route composited in via the route hero's drawing. Internal so the sample renderer
    /// and tests can produce the exact export background.
    ///
    /// - Parameter dimension: `.threeD` raises the route off the roads as a 2.5D ribbon
    ///   and frames the region with headroom above it for the lifted line.
    /// - Parameter aspectRatio: The card the snapshot has to fill — it decides both the
    ///   snapshot's size and the band the route is framed into.
    @MainActor
    static func mapBackground(
        for route: WorkoutRoute,
        tint: UIColor,
        dimension: WorkoutShareRouteDimension,
        aspectRatio: WorkoutShareAspectRatio
    ) async -> UIImage? {
        // Drop non-finite/out-of-range fixes before any bounds math (matching
        // WorkoutShareRouteProjection) — one NaN latitude would otherwise poison
        // the min/max region and the composited polyline.
        let validCoordinates = route.coordinates.filter {
            $0.latitude.isFinite && $0.longitude.isFinite &&
            abs($0.latitude) <= 90 && abs($0.longitude) <= 180
        }
        let coordinates = validCoordinates.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        guard coordinates.count >= 2 else { return nil }

        // Unit lift per fix, index-aligned with `validCoordinates` (the projection
        // filters by the same predicate). A route without usable altitude comes back
        // nil and simply draws flat — the 3D row is unavailable for it anyway.
        let lift = dimension == .threeD ? WorkoutRoute3DProjection.liftUnits(for: validCoordinates) : nil

        // The classic layout is the only one a map background ever draws, and it ignores
        // the landscape arrangement — so `.stacked` here is a constant, not a choice.
        let geometry = WorkoutShareCardGeometry(
            aspectRatio: aspectRatio,
            layout: .classic,
            arrangement: .stacked
        )

        let options = MKMapSnapshotter.Options()
        options.region = mapRegion(
            for: coordinates,
            liftFraction: lift?.max() ?? 0,
            size: geometry.size,
            band: geometry.mapBand
        )
        options.size = geometry.size
        options.scale = 3
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)

        guard let result = try? await MKMapSnapshotter(options: options).start() else {
            return nil
        }
        // A route the projection rejects as GPS jitter renders the map alone — the
        // same metrics-only fallback the preset card gives that input, rather than
        // compositing noise into a misleading trace.
        guard WorkoutShareRouteProjection.normalizedPoints(for: validCoordinates) != nil else {
            return result.image
        }
        return BodyWorkoutRouteMapHero.draw(route: validCoordinates, on: result, fallbackTint: tint, lift: lift)
    }

    /// Region placing the route inside the card's no-fading band — the clear area
    /// between the map scrims (`WorkoutShareCardGeometry.mapBand`). The route's
    /// northmost/southmost points bound onto that band's edges and its center sits at
    /// the band's center, so the trace never runs under the shaded header or metrics
    /// areas, on any ratio.
    ///
    /// - Parameter liftFraction: The 3D ribbon's tallest lift, in ground spans (0 for a
    ///   flat route). The ribbon stands straight up on screen, so the region grows by
    ///   that much on the north side and the lifted line clears the header scrim.
    /// - Parameters size, band: The card's point size and its clear band — passed in
    ///   from the geometry rather than hard-coded, so the region can't be framed for a
    ///   different shape than the snapshot is taken at.
    private static func mapRegion(
        for coordinates: [CLLocationCoordinate2D],
        liftFraction: Double,
        size: CGSize,
        band: (top: CGFloat, bottom: CGFloat)
    ) -> MKCoordinateRegion {
        let cardWidth = Double(size.width), cardHeight = Double(size.height)
        let bandTop = Double(band.top), bandBottom = Double(band.bottom)
        let bandHeight = bandBottom - bandTop
        let bandCenterY = (bandTop + bandBottom) / 2

        // Unwrap longitudes around the first point (as WorkoutShareRouteProjection
        // does) so an antimeridian-crossing route bounds to its true small span, not
        // a near-360° one that would zoom the snapshot out to the whole globe.
        let referenceLongitude = coordinates[0].longitude
        var minLat = coordinates[0].latitude, maxLat = coordinates[0].latitude
        var minLon = referenceLongitude, maxLon = referenceLongitude
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            var longitude = coordinate.longitude
            while longitude - referenceLongitude > 180 { longitude -= 360 }
            while longitude - referenceLongitude < -180 { longitude += 360 }
            minLon = min(minLon, longitude)
            maxLon = max(maxLon, longitude)
        }

        let routeLatSpan = max(maxLat - minLat, 0.0016)
        let midLatitude = (minLat + maxLat) / 2
        let longitudeScale = cos(midLatitude * .pi / 180)
        // Longitude span in latitude-equivalent ground degrees.
        let routeLonSpanAdjusted = max((maxLon - minLon) * longitudeScale, 0.0016)

        // North-side headroom for the lifted line. The draw side raises each point by
        // `liftUnits × max(bboxWidth, bboxHeight)` in snapshot points, so the same ratio
        // of the route's larger ground span is the matching padding here. Over a
        // card-sized region Mercator and equirectangular agree closely enough that the
        // two land on the same place; the residual is well under a pixel.
        let northPadding = max(liftFraction, 0) * max(routeLatSpan, routeLonSpanAdjusted)
        let paddedLatSpan = routeLatSpan + northPadding
        let paddedMidLatitude = midLatitude + northPadding / 2

        // Visible latitude span: the route renders ~2× the band height (centered
        // near the band, extending into the scrims' faded edges — full-band-only
        // read as too small), while its longitude extent stays within ~92% of the
        // width so wide routes never clip horizontally. The rendered extent is exactly
        // that divisor, so it's capped at 75% of the card height — 9:16's band gives
        // 300 of 640 and is unaffected, and no ratio whose scrims leave a tall band can
        // push the trace (plus its 3D lift) past the card's edges.
        let visibleLatSpan = max(
            paddedLatSpan * cardHeight / min(bandHeight * 2.0, 0.75 * cardHeight),
            routeLonSpanAdjusted / 0.92 * cardHeight / cardWidth
        )

        // Shift the map center north of the route center so the route's center lands
        // slightly below the band's center (below the card's midline; screen y grows
        // southward) — nudged down to sit clear of the taller header shade.
        let routeCenterY = bandCenterY + 20
        let centerLatitude = paddedMidLatitude + (routeCenterY - cardHeight / 2) / cardHeight * visibleLatSpan

        // The unwrapped midpoint can land outside ±180°; wrap it back to a valid
        // longitude for the region center.
        var centerLongitude = (minLon + maxLon) / 2
        while centerLongitude > 180 { centerLongitude -= 360 }
        while centerLongitude < -180 { centerLongitude += 360 }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: centerLatitude,
                longitude: centerLongitude
            ),
            // Longitude delta matched exactly to the card's aspect so the snapshotter's
            // region fitting agrees with the latitude-based placement above.
            span: MKCoordinateSpan(
                latitudeDelta: visibleLatSpan,
                longitudeDelta: visibleLatSpan * (cardWidth / cardHeight) / longitudeScale
            )
        )
    }

    private enum ShareError: Error {
        case decodeFailed
    }

    /// Downscales with EXIF orientation baked in via `CGImageSource` thumbnailing —
    /// runs off the main actor so a large cloud photo never stalls the UI.
    nonisolated private static func downscaledImage(from data: Data, maxPixelSize: Int) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ShareError.decodeFailed
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ShareError.decodeFailed
        }
        return UIImage(cgImage: cgImage)
    }
}

/// The backing behind each toolbar icon. On iOS 26 the toolbar draws native Liquid
/// Glass around the item, so the label stays bare; earlier releases get a matching
/// circular material puck instead of an unbacked glyph on the tinted backdrop.
private struct ShareToolbarIconChrome: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
    }
}

/// The long card's natural height, measured inside the preview's scroll view.
private struct LongCardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// What the map-loading task keys on: the snapshot it should be holding. Any change —
/// switching to or from Map, the dimension on screen flipping under a Pro lapse or
/// restore, or a new aspect ratio — restarts the task against the newly needed image.
private struct MapLoadKey: Equatable {
    let isMapActive: Bool
    let dimension: WorkoutShareRouteDimension
    let aspectRatio: WorkoutShareAspectRatio
}

/// The in-flight half of an adjust gesture: the composite gesture's drag and
/// pinch as one `@GestureState` value, already converted from preview to card points.
private struct WorkoutShareInfoGesture: Equatable {
    var translation: CGSize = .zero
    var magnification: CGFloat = 1

    static let idle = WorkoutShareInfoGesture()
}

private struct WorkoutSharePayload: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// The exported MP4 waiting for the share sheet. Its own id (not the clip's) so sharing
/// the same clip twice presents the sheet twice; `clipID` says which scratch directory
/// the file lives in, and so what the share sheet is keeping alive.
private struct WorkoutShareVideoPayload: Identifiable {
    let id = UUID()
    let url: URL
    let clipID: UUID
}

/// Wraps `UIActivityViewController` so the system share sheet can be presented via
/// `.sheet(item:)` — embedding it in a sheet also avoids the iPad popover-anchor crash.
/// Takes the activity items as-is: a `UIImage` for a card, a file URL for a video.
private struct BodyShareActivityView: UIViewControllerRepresentable {
    let items: [Any]
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onComplete() }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// The tray tile scroller: a soft fade over each edge, and a content margin of exactly
/// that width on each end. The two are what make the fade self-correcting — an edge
/// with nothing hidden behind it has an empty `fade`-wide gutter under the gradient, so
/// the fade shows only where a tile is actually passing under an edge. Tracking which
/// edges overflow was the earlier approach, and it left hard-cut tiles wherever the
/// scroll view had no geometry *change* to report.
private struct BodyOptionTileScroller<Content: View>: View {
    let anchor: UnitPoint
    let fade: CGFloat
    let spacing: CGFloat
    let content: Content

    init(
        anchor: UnitPoint,
        fade: CGFloat,
        spacing: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.anchor = anchor
        self.fade = fade
        self.spacing = spacing
        self.content = content()
        _position = State(initialValue: ScrollPosition(edge: anchor.x >= 0.5 ? .trailing : .leading))
    }

    /// The row's resting place. `defaultScrollAnchor(_:for: .initialOffset)` decides it
    /// once, against whatever sizes the first layout pass happened to have — a tray
    /// whose width lands a pass later (the rail's tray budget arrives with the page
    /// width, and the tray itself animates in) was left resting at the leading edge,
    /// with its last tiles cut off behind the rail. Owning the position instead lets
    /// `pinToAnchor` re-pin once the measured layout settles.
    @State private var position: ScrollPosition
    /// Measured widths, watched only as the signal that the layout moved.
    @State private var viewportWidth: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    /// True once the row has been dragged. From then on it stays where the user left
    /// it: picking a metric widens its chip (the checkmark appears), and re-pinning on
    /// that width change threw the row back to its first chip mid-selection.
    @State private var hasUserScrolled = false

    private var restingEdge: Edge {
        anchor.x >= 0.5 ? .trailing : .leading
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                content
            }
            .padding(.vertical, 2)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: OptionTileContentWidthKey.self, value: proxy.size.width)
                }
            }
        }
        .contentMargins(.horizontal, fade, for: .scrollContent)
        // Alignment only — where a row too short to scroll sits, hugging the rail. The
        // initial offset and every re-pin are `position`'s job.
        .defaultScrollAnchor(anchor, for: .alignment)
        .scrollPosition($position)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: OptionTileViewportWidthKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(OptionTileContentWidthKey.self) { width in
            contentWidth = width
        }
        .onPreferenceChange(OptionTileViewportWidthKey.self) { width in
            viewportWidth = width
        }
        .onChange(of: contentWidth) { pinToAnchor() }
        .onChange(of: viewportWidth) { pinToAnchor() }
        .onScrollPhaseChange { _, phase in
            // `.animating` is `pinToAnchor`'s own scroll, which must not count as the
            // user taking the row over.
            if phase == .tracking || phase == .interacting {
                hasUserScrolled = true
            }
        }
        .mask(
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: fade)
                Rectangle().fill(Color.black)
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: fade)
            }
        )
    }

    /// Puts the row back on its anchor after a layout change — unless the user has
    /// already scrolled it somewhere of their own.
    private func pinToAnchor() {
        guard !hasUserScrolled else {
            return
        }

        // The tray opens inside `withAnimation(.snappy)`; without this the pin would
        // inherit it and the row would sweep into place instead of already being there.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            position.scrollTo(edge: restingEdge)
        }
    }
}

private struct OptionTileContentWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct OptionTileViewportWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
