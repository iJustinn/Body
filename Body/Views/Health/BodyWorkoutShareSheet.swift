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
    /// The detail page's lazily fetched full-resolution heart rate, when it has landed.
    /// `presentation` already carries it; this is what the long image's splits need so
    /// their per-split heart rate matches the page's chart. nil keeps the workout's
    /// ≤96-point summary samples.
    let heartRateSamplesOverride: [WorkoutHeartRateSample]?
    /// The month this sheet is sharing *instead of* a workout — `nil` for every caller
    /// that came from a detail page, which is what keeps the workout flow untouched.
    /// Its presence is the single switch summary mode turns on (`isSummaryMode`).
    let monthSummary: WorkoutShareMonthSummary?
    /// "Today" for the summary card's calendar, captured once when the sheet first
    /// appears. The preview and the export are two separate renders; reading `Date()`
    /// inside each would let a midnight crossing between them ship an image the user
    /// never saw. `@State` rather than a stored `let`: the detail page's cover closure
    /// re-evaluates while the sheet is up, and a fresh `Date()` per re-evaluation would
    /// re-render every summary card body for a value that never changes.
    @State private var summaryReferenceDate = Date()

    @Environment(BodyProStore.self) private var proStore: BodyProStore?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workoutColorPalette) private var workoutColorPalette

    @AppStorage(BodyWorkoutShareBackgroundChoice.storageKey) private var storedBackground: String =
        BodyWorkoutShareBackgroundChoice.preset(.midnight).rawValue
    @AppStorage(WorkoutShareRouteDimension.storageKey) private var storedDimension: String =
        WorkoutShareRouteDimension.twoD.rawValue
    @AppStorage(WorkoutShareRouteVisibility.storageKey) private var storedRouteVisibility: String =
        WorkoutShareRouteVisibility.shown.rawValue
    @AppStorage(WorkoutShareIconVisibility.storageKey) private var storedIconVisibility: String =
        WorkoutShareIconVisibility.shown.rawValue
    @AppStorage(WorkoutShareWeekdayVisibility.storageKey) private var storedWeekdayVisibility: String =
        WorkoutShareWeekdayVisibility.shown.rawValue
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
    /// The month-summary card's pick, under its own key again: a month has no single
    /// workout type to file a selection under, so this one is a plain JSON `[String]`
    /// rather than the per-type blob above.
    @AppStorage(WorkoutShareMetricSelection.summaryStorageKey) private var storedSummaryMetricSelections: String = ""
    /// How many activity bars the month card's breakdown draws. A plain count rather
    /// than a selection: the chart ranks the month's activities itself, so the only
    /// choice is how far down that ranking the card goes.
    @AppStorage(WorkoutShareSummaryBarCount.storageKey) private var storedSummaryBarCount: Int =
        WorkoutShareSummaryBarCount.defaultCount
    /// Card or long image. Pro-gated through `resolvedOutputStyle`, so a lapse falls
    /// back to the card for the session without rewriting the key.
    @AppStorage(WorkoutShareOutputStyle.storageKey) private var storedOutputStyle: String =
        WorkoutShareOutputStyle.card.rawValue
    /// The long image's charts are unit-sensitive (splits, elevation, pace), and they
    /// have to read the same preference the detail page just showed the user.
    @AppStorage(BodyAppearancePreference.followsSystemUnitsKey) private var followsSystemUnits = true
    @AppStorage(BodyAppearancePreference.selectedDistanceUnitKey) private var selectedDistanceUnitRawValue =
        BodyValueFormat.DistanceUnitPreference.defaultValue.rawValue
    /// The month summary's Active Energy metric is unit-sensitive the same way the long
    /// image's distances are, and has to read whatever Settings currently says.
    @AppStorage(BodyAppearancePreference.selectedEnergyUnitKey) private var selectedEnergyUnitRawValue =
        BodyValueFormat.EnergyUnitPreference.defaultValue.rawValue

    /// The session-only backdrop, as one value so photo and video can't both be held:
    /// picking either replaces the other, and the two accessors below keep every
    /// existing "is there a photo" read spelled the way it always was.
    private enum SelectedMedia: Equatable {
        case photo(UIImage)
        case video(WorkoutShareVideoClip)
    }

    /// The workout's all-time personal records, read once from the store by
    /// `WorkoutSharePersonalRecordsReader` and handed to the card as a plain value.
    @State private var personalRecords: Set<WorkoutRecordMetric> = []
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
    /// One snapshot per dimension *and* ratio *and* tint: 2D composites the flat route
    /// onto the roads, 3D the lifted ribbon, each ratio frames a differently shaped
    /// region, and the snapshot is baked at the card's own pixel size — so no other
    /// key's image can stand in. Session-only, like the failure set below, and capped:
    /// each entry is a full-card 3x bitmap, so an unbounded dictionary would hold tens
    /// of megabytes after a few ratio and colour passes.
    @State private var mapSnapshots: [MapSnapshotKey: UIImage] = [:]
    /// Insertion order for `mapSnapshots`, oldest first — a Swift dictionary has none of
    /// its own, so the cap needs somewhere to read the eviction candidate from.
    @State private var mapSnapshotOrder: [MapSnapshotKey] = []
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
    /// Which chart the summary card draws. Seeded once from whatever the Workouts page
    /// had on when Share was tapped and never written back: switching the card's chart
    /// must not move the page underneath the sheet. `@State` survives the cover's
    /// re-evaluation (see the initializer's note below), so the pick holds for the
    /// session — and only for the session.
    @State private var summaryChartStyle: WorkoutSummaryChartStyle

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
        /// Summary mode only: a month can be drawn two ways, a workout only one.
        case chartStyle
        /// Summary mode's bar chart only: how far down the month's ranking it goes.
        case barCount
        /// Summary mode's calendar only: whether the grid carries its weekday letters.
        case weekdays
    }

    /// A cached map snapshot's identity: the dimension decides what is composited and
    /// how the region is framed, the ratio decides the snapshot's shape and pixel size.
    private struct MapSnapshotKey: Hashable {
        let dimension: WorkoutShareRouteDimension
        let aspectRatio: WorkoutShareAspectRatio
        /// The resolved workout tint's hex at snapshot time, so a color customization
        /// mid-session can't serve a stale-tinted cached bitmap for an otherwise-identical
        /// dimension/ratio pair.
        let tintHex: String
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
        heartRateRecoveryBPM: Double? = nil,
        heartRateSamplesOverride: [WorkoutHeartRateSample]? = nil
    ) {
        self.workout = workout
        self.route = route
        self.presentation = presentation
        self.heartRateSamplesOverride = heartRateSamplesOverride
        self.splitData = splitData
        self.metricSeries = metricSeries
        self.maxHeartRate = maxHeartRate
        self.heartRateRecoveryBPM = heartRateRecoveryBPM
        // The workout entry point is never the summary one: no month, and the chart
        // style is seeded to a value nothing here ever reads.
        self.monthSummary = nil
        _summaryChartStyle = State(initialValue: .calendar)

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

    /// The month-summary entry point, from the Workouts page's search row. Everything
    /// the workout flow feeds off is empty here — no route, no splits, no series, no
    /// metric pool, no Details tiles — because the summary card reads none of it; the
    /// month's own metric pool is built from the snapshot on demand instead.
    ///
    /// `workout` stays non-optional and takes the summary's *synthetic* zero-duration
    /// stand-in. Some thirty reads of `workout` across this file (the backdrop gradient,
    /// the preset swatches, the icon tile, the map tint) would each need a branch
    /// otherwise — and putting a real workout there would paint a second activity's
    /// colour onto a card meant to carry exactly one.
    init(monthSummary: WorkoutShareMonthSummary) {
        let workout = monthSummary.syntheticWorkout
        self.workout = workout
        self.route = nil
        self.presentation = WorkoutDetailPresentation(workout: workout)
        self.heartRateSamplesOverride = nil
        self.splitData = .empty
        self.metricSeries = .empty
        self.maxHeartRate = nil
        self.heartRateRecoveryBPM = nil
        self.monthSummary = monthSummary
        self.availableMetricOptions = []
        self.defaultMetricIDs = []
        self.longTilePool = []
        self.routePoints = nil
        self.route3D = nil
        // The page's own chart toggle, copied once — see `summaryChartStyle`.
        _summaryChartStyle = State(initialValue: monthSummary.initialChartStyle)
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

    /// The month's metric pool, in card order. Empty outside summary mode — nothing
    /// reads it there, and there is no snapshot to build it from.
    private var activeSummaryMetricOptions: [WorkoutShareSummaryMetricOption] {
        guard let monthSummary else { return [] }
        return WorkoutShareSummaryMetricsBuilder.availableMetrics(
            snapshot: monthSummary.snapshot,
            distanceUnitPreference: distanceUnitPreference,
            energyUnitPreference: energyUnitPreference
        )
    }

    /// What the summary card is showing: the remembered pick narrowed to this month's
    /// pool, or the automatic defaults — and always the defaults without Pro, without
    /// touching what's stored, exactly like the workout card.
    ///
    /// The defaults are intersected with the pool *before* the Pro seam, which hands
    /// them straight back; both defaults are always-on metrics today, but the guard
    /// keeps a free user's card honest should that ever change, and the `prefix(1)`
    /// is the fallback for a pool that shares nothing with the defaults at all.
    private var activeSummaryMetricIDs: [String] {
        let pool = activeSummaryMetricOptions
        let order = pool.map(\.id)
        let wanted = Set(WorkoutShareSummaryMetricsBuilder.defaultIDs)
        let poolDefaults = order.filter { wanted.contains($0) }
        return WorkoutShareBackgroundPolicy.resolvedMetricIDs(
            WorkoutShareMetricSelection.resolvedSummary(
                stored: WorkoutShareMetricSelection.storedSummary(json: storedSummaryMetricSelections),
                available: pool,
                defaults: WorkoutShareSummaryMetricsBuilder.defaultIDs
            ),
            defaults: poolDefaults.isEmpty ? Array(order.prefix(1)) : poolDefaults,
            isProUnlocked: isProUnlocked
        )
    }

    /// How many activities this month has to rank — the ceiling on the bar pick, and
    /// what decides whether the tray offers the choice at all.
    private var summaryBarTypeCount: Int {
        monthSummary?.snapshot.workoutTypeBreakdown.count ?? 0
    }

    /// The bar count the card draws: the remembered pick, clamped to the month's own
    /// activity count without rewriting what's stored — a leaner month must not erase a
    /// pick a richer one will honour again.
    private var activeSummaryBarCount: Int {
        WorkoutShareSummaryBarCount.resolved(
            stored: storedSummaryBarCount,
            availableTypeCount: summaryBarTypeCount
        )
    }

    /// What Share and Save actually produce. Pro-gated, session-only: a lapse renders
    /// the card without rewriting the stored style. A month summary has no long image
    /// at all — no Details tiles, no charts to stack — so a stored `.longImage` left
    /// over from a workout share resolves back to the card here rather than rendering
    /// a page that doesn't exist.
    private var activeOutputStyle: WorkoutShareOutputStyle {
        WorkoutShareBackgroundPolicy.resolvedOutputStyle(
            WorkoutShareOutputStyle.stored(rawValue: storedOutputStyle),
            isProUnlocked: isProUnlocked,
            supportsLongImage: !isSummaryMode
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

    /// The one switch between the two things this sheet can share.
    private var isSummaryMode: Bool { monthSummary != nil }

    /// The activity whose colour the whole page is tinted by — the month's leading type
    /// in summary mode, the workout's own everywhere else. Read by the backdrop, the
    /// preset swatches, and the route-colour tiles so exactly one activity's colour is
    /// ever on screen; the synthetic workout carries the same type, so the two agree.
    private var activeTintType: BodyWorkoutType { monthSummary?.tintType ?? workout.type }

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

    /// The summary calendar's weekday letters. Stored, like the icon toggle.
    private var isWeekdayHeaderHidden: Bool {
        WorkoutShareWeekdayVisibility.stored(rawValue: storedWeekdayVisibility) == .hidden
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
            isProUnlocked: isProUnlocked,
            // The summary never offers a landscape tile, so a remembered one can't
            // render a shape the tray doesn't show.
            supportsLandscape: !isSummaryMode
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
        MapSnapshotKey(
            dimension: activeDimension,
            aspectRatio: activeAspectRatio,
            tintHex: BodyWorkoutColorOverrides.hexText(from: workoutColorPalette.resolvedHex(for: workout.type))
        )
    }

    private var activeMapSnapshot: UIImage? { mapSnapshots[activeMapKey] }

    /// What the sheet restores on open — the map unless a preset (or transparent) was
    /// last picked, never the map without a route to draw, and never transparent without
    /// the Pro entitlement that unlocks it. Both fallbacks are session-only: the stored
    /// key is left exactly as the user set it.
    private var selectedChoice: BodyWorkoutShareBackgroundChoice {
        WorkoutShareBackgroundPolicy.resolvedBackgroundChoice(
            BodyWorkoutShareBackgroundChoice.stored(rawValue: storedBackground, hasRoute: hasRoute),
            isProUnlocked: isProUnlocked
        )
    }

    /// The persisted choice is not the same thing as what's on screen: a session-only
    /// photo sits on top of it. Everything that means "what the user is looking at" —
    /// the strip's highlights, the action bar's disable condition, a map load's failure
    /// branch — reads `activeSelection` so a photo over a stored `.map` behaves right.
    private enum ActiveSelection: Equatable {
        case photo
        case video
        case map
        /// The ink is part of the identity: the tray offers a light and a dark
        /// transparent tile, and only one of them may show the selection ring.
        case transparent(WorkoutShareCardInk)
        case preset(BodyWorkoutSharePreset)
    }

    /// `.map` is unreachable without a route: `selectedChoice` already resolves a
    /// stored map to Midnight there, so the layout, the busy state, and the opening
    /// map load all fall out of this one property with no route-less branching.
    private var activeSelection: ActiveSelection {
        if renderablePhoto != nil { return .photo }
        if renderableVideo != nil { return .video }
        if case .transparent(let ink) = selectedChoice { return .transparent(ink) }
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

    /// The background both preview and export use: photo wins, then the preset (or the
    /// transparent pick), then the map's snapshot.
    private var activeBackground: WorkoutShareCardBackground {
        if let renderablePhoto {
            return .photo(renderablePhoto)
        }
        if renderableVideo != nil {
            return .video
        }
        if case .transparent(let ink) = selectedChoice {
            return .transparent(ink)
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
        case .transparent(let ink): return ink
        }
    }

    /// Whether this Share/Save has to be written as a PNG rather than handed over as a
    /// bare `UIImage`. `PHAssetCreationRequest(from:)` encodes JPEG and
    /// `UIActivityViewController` re-encodes at the receiver's discretion, so a card
    /// with a real alpha channel would arrive flattened to black either way. Long mode
    /// never qualifies: the long image paints a gradient (`activeLongPreset`), which is
    /// never transparent.
    private var isTransparentOutput: Bool {
        guard !isLongMode else { return false }
        if case .transparent = activeBackground { return true }
        return false
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
        case .preset, .photo, .video, .transparent: return .centered
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
        return Self.merged(committedInfoTransform, with: live).clamped(cardSize: cardSize).snappedToCenter()
    }

    /// Which centre guides the preview lights up: one per axis the block is currently
    /// snapped onto, and only while a Layout drag is in flight. At rest, or while the
    /// block sits off-centre, nothing is drawn.
    private var activeCenterSnap: WorkoutShareCenterSnap {
        guard isMediaMode, photoStep == .layout, inFlightGesture != .idle else { return .none }
        let offset = activeInfoTransform.offset
        return WorkoutShareCenterSnap(vertical: offset.width == 0, horizontal: offset.height == 0)
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

    /// The one seam the two kinds of card meet at: the preview, the export's
    /// rasterization, and — through that rasterization — the video overlay all draw
    /// whatever this returns, so summary mode reaches every output through one branch.
    @ViewBuilder
    private func cardView() -> some View {
        if let monthSummary {
            summaryCardView(monthSummary)
        } else {
            workoutCardView()
        }
    }

    /// The month's card. Same background, ratio, transforms, font, and attribution as
    /// the workout card — only the content inside the info block differs.
    private func summaryCardView(_ summary: WorkoutShareMonthSummary) -> BodyWorkoutShareSummaryCardView {
        // Resolved once per card, not once per lookup: this runs on every gesture frame,
        // and each read rebuilds the pool and decodes the stored JSON.
        let pool = activeSummaryMetricOptions
        let ids = activeSummaryMetricIDs
        return BodyWorkoutShareSummaryCardView(
            summary: summary,
            palette: workoutColorPalette,
            chartStyle: summaryChartStyle,
            showsWeekdayHeader: !isWeekdayHeaderHidden,
            barRowCount: activeSummaryBarCount,
            // Pool order, so the card's strip reads the way the chips are laid out.
            metrics: ids.compactMap { id in pool.first { $0.id == id } },
            background: activeBackground,
            aspectRatio: activeAspectRatio,
            infoTransform: activeInfoTransform,
            photoTransform: activePhotoTransform,
            fontDesign: storedFontChoice.design,
            attribution: activeAttribution,
            referenceDate: summaryReferenceDate
        )
    }

    private func workoutCardView() -> BodyWorkoutShareCardView {
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
            palette: workoutColorPalette,
            background: activeBackground,
            layout: cardLayout,
            aspectRatio: activeAspectRatio,
            arrangement: activeArrangement,
            infoTransform: activeInfoTransform,
            photoTransform: activePhotoTransform,
            fontDesign: storedFontChoice.design,
            routeColor: storedRouteColorChoice.color(tint: workoutColorPalette.color(for: workout.type)),
            attribution: activeAttribution,
            personalRecords: personalRecords
        )
    }

    /// The unit the long image's splits, elevation, and pace are drawn in — the same
    /// preference the detail page just used, so the export matches the page.
    private var distanceUnitPreference: BodyValueFormat.DistanceUnitPreference {
        followsSystemUnits
            ? BodyValueFormat.DistanceUnitPreference.systemValue(locale: .current)
            : BodyValueFormat.DistanceUnitPreference.storedValue(from: selectedDistanceUnitRawValue)
    }

    /// The unit the month summary's Active Energy is drawn in. Same shape as the
    /// distance preference above — the "follows system" switch covers energy too, and
    /// the card has to read whatever the Workouts page just showed the user.
    private var energyUnitPreference: BodyValueFormat.EnergyUnitPreference {
        followsSystemUnits
            ? BodyValueFormat.EnergyUnitPreference.systemValue(locale: .current)
            : BodyValueFormat.EnergyUnitPreference.storedValue(from: selectedEnergyUnitRawValue)
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
            workout: workout,
            splitData: splitData,
            distanceUnitPreference: distanceUnitPreference,
            heartRateSamplesOverride: heartRateSamplesOverride
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
            palette: workoutColorPalette,
            preset: activeLongPreset,
            fontDesign: storedFontChoice.design,
            routeColor: storedRouteColorChoice.color(tint: workoutColorPalette.color(for: workout.type)),
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
                        .snappedToCenter()
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
                        // Two pools, two trays: the month's chips toggle a plain list
                        // under its own key, the workout's a per-type blob.
                        Group {
                            if isSummaryMode {
                                summaryMetricsTray
                            } else {
                                metricsTray
                            }
                        }
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
                // Resolved through a zero-sized child rather than an `@EnvironmentObject`
                // on the sheet: the store publishes throughout a background refresh, and
                // observing it here would invalidate the whole composer — gestures and
                // all — on every one of those. The set is captured into state, so the
                // card renderers stay static.
                if !isSummaryMode {
                    WorkoutSharePersonalRecordsReader(workout: workout) { records in
                        // The baseline scan can finish with the composer already open,
                        // so the badge fades onto the live preview instead of popping
                        // into the middle of a card the user is looking at.
                        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.3)) {
                            personalRecords = records
                        }
                    }
                }

                GeometryReader { proxy in
                    // Two rails rather than one filtered rail: they disagree about more
                    // than which rows show — see `summaryOptionRail`.
                    if isSummaryMode {
                        summaryOptionRail(availableWidth: proxy.size.width)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    } else {
                        optionRail(availableWidth: proxy.size.width)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    }
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

                        Text("v6")
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
                    .accessibilityLabel(isSummaryMode ? Text("Share Summary") : Text("Share Workout"))
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
            // A transparent card ships as a `.png` file so its alpha survives the hand-off;
            // every other card is the `UIImage` it always was. The file has to outlive the
            // share sheet, so it goes when the payload is cleared.
            .sheet(item: $payload) { payload in
                BodyShareActivityView(items: [payload.pngURL ?? payload.image]) {
                    self.payload = nil
                    if let url = payload.pngURL { Self.removeSharePNG(at: url) }
                }
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
            .onChange(of: activeAspectRatio) { _, newRatio in
                resetPhotoAdjustments()
                evictMapSnapshots(keeping: newRatio)
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
            // receive any more, the player, and every scratch directory nothing else
            // is still reading.
            .onDisappear {
                videoExportTask?.cancel()
                videoExportTask = nil
                teardownPreviewPlayer()
                // Retired, not deleted outright: the system share panel over this sheet
                // holds the exported file, and a save may still be writing it. Whichever
                // of those finishes last runs the removal.
                if let clip = selectedVideo {
                    pendingScratchIDs.append(clip.id)
                }
                removePendingScratch()
            }
            // Opens on the map without waiting for a tap, and re-fires whenever the
            // snapshot on screen changes identity — so a Pro lapse (3D → 2D, or a
            // landscape ratio → 9:16), a restore, or a new ratio pick loads the newly
            // active snapshot on its own.
            .task(id: MapLoadKey(
                isMapActive: activeSelection == .map,
                dimension: activeDimension,
                aspectRatio: activeAspectRatio,
                tintHex: activeMapKey.tintHex
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
            colors: [workoutColorPalette.color(for: activeTintType).opacity(0.45), Color.black],
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
                            if isTransparentOutput {
                                // Under the card, never inside it: `cardView()` is what
                                // rasterizes, so the checkerboard can't reach the export.
                                // It stands in for the alpha the PNG actually carries,
                                // using the convention every image editor uses.
                                WorkoutShareTransparencyChecker()
                                    .frame(width: cardSize.width, height: cardSize.height)
                            }

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

                        // Centre guides for placing the block: each line appears only
                        // while the block is snapped onto that axis mid-drag. Drawn here,
                        // outside `cardView()`, so they never reach the export, and in
                        // the card's ink so they read on a light preset and a dark photo.
                        WorkoutShareCenterGuides(color: activeInk.primary, snap: activeCenterSnap)
                            .frame(width: cardSize.width, height: cardSize.height)
                            .scaleEffect(previewScale, anchor: .topLeading)
                            .allowsHitTesting(false)
                            .sensoryFeedback(.alignment, trigger: activeCenterSnap) { _, new in
                                new.vertical || new.horizontal
                            }

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

    /// The month summary's rail: Font, Chart Style, Metrics, Profile, Background, Ratio
    /// — the workout rail's order, with Chart Style where Route Style would be.
    /// A separate rail rather than a filtered `optionRail`, because the two disagree
    /// about more than which rows appear — a month has no trace to colour, style, or
    /// arrange; its Ratio tray drops the Long Image tile; and Chart Style exists nowhere
    /// else. (The workout rail is also scanned verbatim by a source guard that pins its
    /// row order, so it stays a straight-line list of rows.)
    private func summaryOptionRail(availableWidth: CGFloat) -> some View {
        // Same budget as the workout rail: what's left of the page beside the icons, so
        // an open tray can never run under the trailing edge.
        let trayWidth = max(
            Self.optionTileSize,
            availableWidth - Self.railPadding * 2 - Self.railIconSize - Self.railTrayGap
        )

        return VStack(alignment: .trailing, spacing: 22) {
            // Same pinned Latin "Aa" glyph as the workout rail: `textformat` localizes
            // itself into "格式" (Format), which names the wrong thing.
            railRow(.font, icon: Self.fontRailIcon, label: Text("Font"), trayWidth: trayWidth) {
                optionTiles {
                    ForEach(WorkoutShareFontChoice.allCases) { choice in
                        fontTile(choice)
                    }
                }
            }

            // The one row that exists only here, in the slot the workout rail gives
            // Route Style — what the card draws comes right after how it's lettered.
            // Free: the chart *is* the card in summary mode, not an upgrade to it.
            railRow(
                .chartStyle,
                symbol: "chart.bar.doc.horizontal",
                label: Text("Chart Style"),
                trayWidth: trayWidth
            ) {
                chartStyleTray
            }

            // Each chart's own row, directly under the style it belongs to, in the
            // styles' own order. Only one of the two is ever on the rail, since a
            // calendar has no bars to count and a bar chart has no weekday letters.
            if summaryChartStyle == .calendar {
                railRow(.weekdays, symbol: "abc", label: Text("Weekdays"), trayWidth: trayWidth) {
                    weekdayTray
                }
            }

            // A month with a single activity has nothing to choose between — its one bar
            // is every bar — so the row leaves with the choice rather than offering a
            // tile that can't be tapped off.
            let barCounts = WorkoutShareSummaryBarCount.options(availableTypeCount: summaryBarTypeCount)
            if summaryChartStyle == .bar, !barCounts.isEmpty {
                railRow(.barCount, symbol: "list.number", label: Text("Bars"), trayWidth: trayWidth) {
                    barCountTray(barCounts)
                }
            }

            // Pro-only and opening below the preview rather than beside the icon, for
            // the reason the workout card's chips do: a rich month offers seven names,
            // which would run straight under the card's own metric strip. The square
            // card is the chart alone, so the row goes away with it rather than
            // editing a pick nothing draws.
            if activeAspectRatio != .square {
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
            }

            railRow(.profile, symbol: "at", label: Text("Profile"), trayWidth: trayWidth) {
                profileTray
            }

            // Presets, Photo, and Video. The tray's Map tile is already behind
            // `if hasRoute`, and a month never has one, so it drops out on its own.
            railRow(
                .background,
                symbol: "photo.on.rectangle",
                label: Text("Background"),
                trayWidth: trayWidth
            ) {
                backgroundTray
            }

            railRow(.ratio, symbol: "aspectratio", label: Text("Ratio"), trayWidth: trayWidth) {
                summaryRatioTray
            }
        }
        .padding(.trailing, Self.railPadding)
        // Same reason as the workout rail: a Pro lapse while the chips are open would
        // leave them editing a pick the card no longer honours.
        .onChange(of: isProUnlocked) {
            if !isProUnlocked, expandedOption == .metrics { closeTray() }
        }
        // Bars belongs to the bar chart and Weekdays to the calendar; switching charts
        // takes one of them off the rail, so its tray goes with it.
        .onChange(of: summaryChartStyle) {
            if summaryChartStyle != .bar, expandedOption == .barCount { closeTray() }
            if summaryChartStyle != .calendar, expandedOption == .weekdays { closeTray() }
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
                // Two tiles, one per ink: a transparent export has nothing behind its
                // text to derive the polarity from, so which way it runs is the user's
                // pick. Dimmed in long mode with the map/photo/video tiles — the long
                // image always paints a gradient.
                transparentTile(ink: .light)
                    .opacity(isLongMode ? 0.4 : 1)
                    .disabled(isLongMode)
                transparentTile(ink: .dark)
                    .opacity(isLongMode ? 0.4 : 1)
                    .disabled(isLongMode)
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
                    Text("Pick up to 5 metrics.")
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
    /// bounds impossible to feel. The card has no floor — its last chip turns off too,
    /// leaving the route and the branding alone; only the long image keeps one on.
    private func metricChip(_ option: WorkoutShareMetricOption) -> some View {
        let isLong = isLongMode
        let ids = isLong ? activeLongMetricIDs : activeMetricIDs
        let isSelected = ids.contains(option.id)
        // The long image has no ceiling to dim against.
        let isAtMaximum = !isLong && ids.count >= WorkoutShareMetricSelection.maximumCount
        // Only the long image still has a floor to explain: the card's last chip
        // turns off like any other.
        let isLastLongMetric = isLong && isSelected && ids.count == 1
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
            isLastLongMetric ? Text("At least one metric stays on the long image.") : Text(verbatim: "")
        )
    }

    /// The month's chips. Same strip, same bounds, same caption as the workout card's —
    /// only the pool differs, so anyone who has shared a workout already reads this.
    /// There is no long-image branch here: summary mode has no long image.
    private var summaryMetricsTray: some View {
        VStack(alignment: .center, spacing: 6) {
            optionTiles(anchor: .leading) {
                ForEach(activeSummaryMetricOptions) { option in
                    summaryMetricChip(option)
                }
            }

            Text("Pick up to 3 metrics.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        // Full-width strip under the card, like the workout tray: the scroller isn't
        // sized by the rail's budget, and a tap between chips reaches nothing behind it.
        .frame(maxWidth: .infinity)
    }

    /// One pickable month metric. As with the workout chip, a tap doesn't close the
    /// tray and there is no floor: the last chip turns off too, and the card goes back
    /// to the title and the chart.
    private func summaryMetricChip(_ option: WorkoutShareSummaryMetricOption) -> some View {
        let pool = activeSummaryMetricOptions
        let ids = activeSummaryMetricIDs
        let isSelected = ids.contains(option.id)
        let isAtMaximum = ids.count >= WorkoutShareMetricSelection.summaryMaximumCount
        return Button {
            let next = WorkoutShareMetricSelection.togglingSummary(option.id, in: ids, available: pool)
            guard next != ids else { return }
            storedSummaryMetricSelections = WorkoutShareMetricSelection.storingSummary(next)
        } label: {
            HStack(spacing: 4) {
                if isSelected {
                    // The `.isSelected` trait below already says this to VoiceOver.
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .accessibilityHidden(true)
                }

                Text(option.title)
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
        // Name plus what it currently reads, so VoiceOver users pick by value the way
        // sighted users do.
        .accessibilityLabel(Text(verbatim: "\(option.title), \(option.value)"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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

    /// The month summary's Ratio tray: the five shapes and nothing else. The long image
    /// is the detail page's tiles and charts stacked, and a month has neither, so the
    /// sixth tile isn't offered here at all.
    private var summaryRatioTray: some View {
        optionTiles {
            ForEach(WorkoutShareSummaryCardGeometry.supportedAspectRatios) { ratio in
                ratioTile(ratio)
            }
        }
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

    /// Calendar grid or activity bars. Two tiles rather than a switch, so the row reads
    /// like every other tray on the rail — and free, since the chart is the card's whole
    /// content here rather than an upgrade to it.
    private var chartStyleTray: some View {
        optionTiles {
            ForEach(WorkoutSummaryChartStyle.allCases) { style in
                chartStyleTile(style)
            }
        }
    }

    /// How far down the month's ranking the bar chart goes. Anchored leading, unlike
    /// the trays above: a count is a scale read from its low end, and resting on the
    /// last tiles would open the tray past the number that's actually picked.
    private func barCountTray(_ counts: [Int]) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            optionTiles(anchor: .leading) {
                ForEach(counts, id: \.self) { count in
                    barCountTile(count)
                }
            }

            Text("How many activity bars the card shows.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One bar-count tile. The number is verbatim: it is the same digit in every
    /// language the app ships, and an interpolated `Text` would file it in the catalog.
    private func barCountTile(_ count: Int) -> some View {
        let isSelected = activeSummaryBarCount == count
        return Button {
            closeTray()
            storedSummaryBarCount = count
        } label: {
            Text(verbatim: "\(count)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: Self.optionTileSize, height: Self.optionTileSize)
                .background(Color.white.opacity(0.1), in: Circle())
                .overlay { selectionRing(isSelected: isSelected) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(count)"))
        .accessibilityHint(Text("How many activity bars the card shows."))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// The calendar's S M T W T F S row, shown or hidden — two tiles rather than one
    /// toggle, the shape the route-less card's Icon row already uses for a choice with
    /// exactly two answers.
    private var weekdayTray: some View {
        optionTiles {
            showWeekdaysTile
            hideWeekdaysTile
        }
    }

    private var showWeekdaysTile: some View {
        let isSelected = !isWeekdayHeaderHidden
        return Button {
            closeTray()
            storedWeekdayVisibility = WorkoutShareWeekdayVisibility.shown.rawValue
        } label: {
            Image(systemName: "abc")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: Self.optionTileSize, height: Self.optionTileSize)
                .background(Color.white.opacity(0.1), in: Circle())
                .overlay { selectionRing(isSelected: isSelected) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Show Weekdays"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var hideWeekdaysTile: some View {
        let isSelected = isWeekdayHeaderHidden
        return Button {
            closeTray()
            storedWeekdayVisibility = WorkoutShareWeekdayVisibility.hidden.rawValue
        } label: {
            Image(systemName: "eye.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Self.optionTileSize, height: Self.optionTileSize)
                .background(Color.white.opacity(0.1), in: Circle())
                .overlay { selectionRing(isSelected: isSelected) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Hide Weekdays"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Ring-only selection over the same glyph the Workouts page's own chart switch
    /// uses, so the two read as the same control. Session-only: the tap moves
    /// `summaryChartStyle` and never the page's stored toggle.
    private func chartStyleTile(_ style: WorkoutSummaryChartStyle) -> some View {
        let isSelected = summaryChartStyle == style
        return Button {
            closeTray()
            withAnimation(reduceMotion ? nil : .snappy) { summaryChartStyle = style }
        } label: {
            Image(systemName: style.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Self.optionTileSize, height: Self.optionTileSize)
                .background(Color.white.opacity(0.1), in: Circle())
                .overlay { selectionRing(isSelected: isSelected) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: style.localizedName))
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
                .fill(choice.color(tint: workoutColorPalette.color(for: activeTintType)))
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
                .fill(preset.gradient(tint: workoutColorPalette.color(for: activeTintType)))
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

    /// No background at all: the card exports as a PNG with a real alpha channel, for
    /// dropping onto a Story, a poster, or a video edit. Pro, and stored like the
    /// presets and the map — `selectedChoice` absorbs a lapse rather than the key being
    /// rewritten. The tile shows the same checkerboard the preview puts behind the card,
    /// so "transparent" reads without a caption.
    private func transparentTile(ink: WorkoutShareCardInk) -> some View {
        let isSelected = activeSelection == .transparent(ink)
        return Button {
            closeTray()
            guard isProUnlocked else {
                showBodyProPaywall = true
                return
            }
            storedBackground = BodyWorkoutShareBackgroundChoice.transparent(ink).rawValue
            // Also resets the picker items, so re-picking the same asset later re-fires
            // the `.task(id:)` load (an unchanged id would silently do nothing).
            replaceMedia(with: nil)
        } label: {
            ZStack {
                WorkoutShareTransparencyChecker(square: 7)
                // The letterform is the swatch: it's the ink itself, which is the only
                // thing that differs between the two tiles.
                Image(systemName: "textformat")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ink.primary)
                    .shadow(color: ink.legibilityShadow, radius: 2, x: 0, y: 0.5)
            }
            .frame(width: Self.optionTileSize, height: Self.optionTileSize)
            .clipShape(Circle())
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 0.5)
                }
            }
            // The checkerboard is mid-gray on every theme, so the edge and the ring stay
            // dark — a white hairline would wash out against it, the way Daylight's does.
            .overlay { Circle().strokeBorder(Color.black.opacity(0.15)) }
            .overlay { selectionRing(isSelected: isSelected, stroke: Color.black.opacity(0.6)) }
            .overlay(alignment: .bottomTrailing) {
                if !isProUnlocked {
                    lockBadge
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ink == .light ? Text("Transparent, White Text") : Text("Transparent, Black Text"))
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

    /// Whether a retired clip's files can go now. False while the system share panel
    /// still holds the exported URL, and while a save is writing it — both outlive the
    /// sheet that made them.
    static func canRemoveScratch(hasVideoPayload: Bool, isSavingImage: Bool) -> Bool {
        !hasVideoPayload && !isSavingImage
    }

    private func removePendingScratch() {
        guard Self.canRemoveScratch(
            hasVideoPayload: videoPayload != nil, isSavingImage: isSavingImage
        ) else { return }
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
            // The rasterization below blocks the main actor for as long as it takes, so
            // yield once first: without it SwiftUI never gets a pass to paint the
            // spinner `isRendering` just turned on, and a long image looks frozen.
            await Task.yield()
            defer { isRendering = false }

            if let image = renderShareImage() {
                // A transparent card is handed over as a file so nothing downstream can
                // re-encode its alpha away. If the write fails there's still a perfectly
                // good image to share — it just arrives flattened — so this falls back
                // rather than failing the share.
                payload = WorkoutSharePayload(
                    image: image,
                    pngURL: isTransparentOutput ? Self.writeSharePNG(image) : nil
                )
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

        // `creationRequestForAsset(from:)` encodes a JPEG, which has no alpha channel —
        // a transparent card saved that way arrives in Photos on a black background. The
        // PNG bytes are added as the asset's photo resource instead. Resolved out here:
        // the change block is `@Sendable` and can't read the sheet's state.
        let pngData = isTransparentOutput ? image.pngData() : nil

        do {
            try await PHPhotoLibrary.shared().performChanges {
                if let pngData {
                    PHAssetCreationRequest.forAsset()
                        .addResource(with: .photo, data: pngData, options: nil)
                } else {
                    PHAssetCreationRequest.creationRequestForAsset(from: image)
                }
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

    /// Writes a transparent card out as a real PNG for the share sheet to carry. Its own
    /// directory per export, so the file can keep a stable, presentable name ("Body.png"
    /// is what the receiving app shows) without two shares in a row colliding. Returns
    /// `nil` on any failure — the caller then shares the `UIImage`, which is the old
    /// behaviour, rather than dropping the share entirely.
    private static func writeSharePNG(_ image: UIImage) -> URL? {
        guard let data = image.pngData() else { return nil }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkoutShareImage-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("Body.png")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            try? FileManager.default.removeItem(at: directory)
            return nil
        }
    }

    /// Takes the whole per-export directory, not just the file inside it.
    private static func removeSharePNG(at url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
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

    /// How many full-card map bitmaps stay in memory at once. Four covers the dimension
    /// and tint passes a user makes on one ratio without holding a session's worth.
    private static let maximumCachedMapSnapshots = 4

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
    /// `sizeThatFits`, so the height comes from a measuring pass — which reports its
    /// `size` in points, so it runs at 0.25 scale and rasterizes ~16x less for a height
    /// that is unchanged. The scale then backs off from 3 so a very tall workout stays
    /// under `maximumLongOutputPixels`; a page so long that even 1x exceeds it renders
    /// nothing and falls into the "Couldn't Create Image" alert rather than allocating a
    /// bitmap that would take the app down.
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
        renderer.scale = 0.25

        guard let measured = renderer.uiImage else { return nil }
        guard let scale = Self.longExportScale(forHeight: measured.size.height) else { return nil }

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

    /// Stores a snapshot, keeping at most `maximumCachedMapSnapshots` of them: the
    /// oldest goes when a new one would push past the cap.
    @MainActor
    private func cacheMapSnapshot(_ image: UIImage, for key: MapSnapshotKey) {
        if mapSnapshots[key] == nil {
            mapSnapshotOrder.append(key)
        }
        mapSnapshots[key] = image
        while mapSnapshotOrder.count > Self.maximumCachedMapSnapshots {
            let oldest = mapSnapshotOrder.removeFirst()
            mapSnapshots.removeValue(forKey: oldest)
        }
    }

    /// Drops every cached, failed and in-flight key framed for a ratio the card is no
    /// longer on. A snapshot is baked for one card shape, so none of them can ever be
    /// shown again in this session unless the user comes back to that ratio, which
    /// re-requests it anyway.
    @MainActor
    private func evictMapSnapshots(keeping aspectRatio: WorkoutShareAspectRatio) {
        mapSnapshots = mapSnapshots.filter { $0.key.aspectRatio == aspectRatio }
        mapSnapshotOrder.removeAll { $0.aspectRatio != aspectRatio }
        failedMapKeys = failedMapKeys.filter { $0.aspectRatio == aspectRatio }
        loadingMapKeys = loadingMapKeys.filter { $0.aspectRatio == aspectRatio }
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
            tint: UIColor(workoutColorPalette.color(for: workout.type)),
            dimension: key.dimension,
            aspectRatio: key.aspectRatio
        )
        if let image {
            // Cache even if the user switched away meanwhile — re-selecting this
            // dimension/ratio then shows the snapshot instantly.
            cacheMapSnapshot(image, for: key)
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
        let validCoordinates = route.coordinates.drawable
        let coordinates = validCoordinates.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        guard coordinates.count >= 2 else { return nil }

        // Unit lift per fix, index-aligned with `validCoordinates`: both sides keep the
        // fixes that pass `isDrawable`. A route without usable altitude comes back
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
    /// Internal rather than private so the tests can frame a region without taking a
    /// snapshot.
    static func mapRegion(
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
    /// Mirrors `MapSnapshotKey.tintHex`: a colour customization mid-session mints a new
    /// snapshot key, so the loading task has to restart for it too. Without this the
    /// sheet would wait forever on a snapshot nobody is fetching, leaving Share and Save
    /// disabled with no loader running.
    let tintHex: String
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
    /// Set only for a transparent card, and then shared *instead of* `image`:
    /// `UIActivityViewController` re-encodes a bare `UIImage` at the receiver's
    /// discretion — JPEG for most of them — which flattens the alpha to black. Handing
    /// over a real `.png` file leaves nothing to re-encode. The file outlives the share
    /// sheet, so it's deleted from the completion handler, like the video's scratch.
    var pngURL: URL?
}

/// The checkerboard drawn *behind* a transparent card in the preview, and
/// inside its tray tiles — the convention every image editor uses to say "this area is
/// alpha". Deliberately not part of `cardView()`: that view is what `ImageRenderer`
/// rasterizes, so anything drawn inside it would end up in the exported PNG.
private struct WorkoutShareTransparencyChecker: View {
    /// Side of one square, in the coordinate space this view is laid out in. The preview
    /// draws it in card points (so it scales with the card); the tiles use a smaller
    /// square, since a 40 pt circle needs more than four squares to read as a pattern.
    var square: CGFloat = 10

    /// Mid-tones rather than the white/near-white pair image editors use. The card drawn
    /// over this is the *user's* pick of ink, and a light checkerboard renders the
    /// white-text option almost invisible — the preview would read as a broken card
    /// rather than as a transparent one. These two are dark enough for white text and
    /// light enough for black, so neither tile is penalised for the backdrop.
    private static let light = Color(white: 0.70)
    private static let dark = Color(white: 0.52)

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.light))
            guard square > 0 else { return }
            let columns = Int(ceil(size.width / square))
            let rows = Int(ceil(size.height / square))
            guard columns > 0, rows > 0 else { return }
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(
                        x: CGFloat(column) * square,
                        y: CGFloat(row) * square,
                        width: square,
                        height: square
                    )
                    context.fill(Path(rect), with: .color(Self.dark))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Which of the card's centre lines the info block is currently snapped onto. The
/// vertical line means the block is horizontally centred, and vice versa.
private struct WorkoutShareCenterSnap: Equatable {
    var vertical: Bool
    var horizontal: Bool

    static let none = WorkoutShareCenterSnap(vertical: false, horizontal: false)
}

/// Hairlines through the card's centre, one per axis the block is snapped onto, so a
/// Layout drag shows the same magnet cue a Story editor does. Preview-only: it lives
/// beside `cardView()`, never inside it, for the same reason as the checkerboard.
private struct WorkoutShareCenterGuides: View {
    let color: Color
    let snap: WorkoutShareCenterSnap

    var body: some View {
        Canvas { context, size in
            var path = Path()
            if snap.vertical {
                path.move(to: CGPoint(x: size.width / 2, y: 0))
                path.addLine(to: CGPoint(x: size.width / 2, y: size.height))
            }
            if snap.horizontal {
                path.move(to: CGPoint(x: 0, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            }
            context.stroke(
                path,
                with: .color(color.opacity(0.55)),
                style: StrokeStyle(lineWidth: 1, dash: [6, 4])
            )
        }
        .accessibilityHidden(true)
    }
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

/// Reads the workout's personal records out of the store and hands them to the sheet
/// as a plain value.
///
/// Its own zero-sized view rather than an `@EnvironmentObject` on the sheet itself:
/// the store publishes on every step of a background refresh, and observing it from
/// the sheet would invalidate the entire composer — preview, rail, and live gesture
/// state — each time. Here the invalidation stops at a view that draws nothing.
private struct WorkoutSharePersonalRecordsReader: View {
    let workout: WorkoutSummary
    let onResolve: (Set<WorkoutRecordMetric>) -> Void

    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .onAppear { onResolve(workoutStore.personalRecords(for: workout)) }
            // The ledger is empty until the one-time baseline scan finishes, which can
            // land while the sheet is already open.
            .onChange(of: workoutStore.recordLedger.baselineComplete) { _, _ in
                onResolve(workoutStore.personalRecords(for: workout))
            }
    }
}
