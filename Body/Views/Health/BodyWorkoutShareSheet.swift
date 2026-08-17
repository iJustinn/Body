//
//  BodyWorkoutShareSheet.swift
//  Body
//
//  Preview-and-share flow for a workout's image. Built like a story composer: the
//  card fills the page scaled to fit whatever shape the chosen aspect ratio gives it,
//  a vertical icon rail sits on the trailing edge, and tapping a rail icon slides that
//  option's tiles out to its left (Font, Ratio, Arrange, Route Color, Background,
//  3D — one tray open at a time); the last icon, Metrics, opens a chip strip under
//  the card instead. Save/Share rasterize the card via
//  `ImageRenderer` at 3×
//  and hand the image (1080 px on its short side) to the photo library or the system
//  share sheet. On a photo background the preview drives two adjust steps: Photo
//  pans/zooms the backdrop, Layout moves and resizes the card's info block — both
//  session-only, and both fed to the export so the image matches the preview. The
//  route is optional: a workout without one (indoor, strength, yoga…) shares the same
//  flow with the map tile and the Route Color / Arrange / 3D rail icons dropped and
//  the card's route-less layout in place of the trace.
//

import SwiftUI
import PhotosUI
import Photos
import ImageIO
import MapKit
import UIKit

struct BodyWorkoutShareSheet: View {
    let workout: WorkoutSummary
    let route: WorkoutRoute?
    let presentation: WorkoutDetailPresentation

    @Environment(BodyProStore.self) private var proStore: BodyProStore?
    @Environment(\.dismiss) private var dismiss

    @AppStorage(BodyWorkoutShareBackgroundChoice.storageKey) private var storedBackground: String =
        BodyWorkoutShareBackgroundChoice.preset(.midnight).rawValue
    @AppStorage(WorkoutShareRouteDimension.storageKey) private var storedDimension: String =
        WorkoutShareRouteDimension.twoD.rawValue
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

    @State private var selectedPhoto: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var isPickerPresented = false
    @State private var isLoadingPhoto = false
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
    /// Which of the two things the photo preview's gestures move. Photo comes first: the
    /// backdrop has to be framed before placing the block on it makes sense.
    @State private var photoStep: PhotoAdjustStep = .photo

    /// Computed once from the shared presentation so the card's values never drift
    /// from the detail page and the projection isn't redone on every body pass.
    /// The pool the Metrics tray offers and the card resolves against, plus what the
    /// card shows when nobody picked. Both depend only on the presentation and the
    /// route's presence, so they're built once here rather than per body pass.
    private let availableMetricOptions: [WorkoutShareMetricOption]
    private let defaultMetricIDs: [String]
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

    init(workout: WorkoutSummary, route: WorkoutRoute?, presentation: WorkoutDetailPresentation) {
        self.workout = workout
        self.route = route
        self.presentation = presentation
        self.availableMetricOptions = WorkoutShareMetricsBuilder.availableMetrics(for: presentation, type: workout.type)
        self.defaultMetricIDs = WorkoutShareMetricsBuilder.defaultMetricIDs(
            for: presentation,
            type: workout.type,
            hasRoute: route != nil
        )
        self.routePoints = route.flatMap { WorkoutShareRouteProjection.normalizedPoints(for: $0.coordinates) }
        self.route3D = route.flatMap { WorkoutRoute3DProjection.projected(for: $0.coordinates) }
    }

    private var isProUnlocked: Bool { proStore?.isPro == true }

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
        case map
        case preset(BodyWorkoutSharePreset)
    }

    /// `.map` is unreachable without a route: `selectedChoice` already resolves a
    /// stored map to Midnight there, so the layout, the busy state, and the opening
    /// map load all fall out of this one property with no route-less branching.
    private var activeSelection: ActiveSelection {
        if renderablePhoto != nil { return .photo }
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

    /// The background both preview and export use: photo wins, then the preset, then
    /// the map's snapshot.
    private var activeBackground: WorkoutShareCardBackground {
        if let renderablePhoto {
            return .photo(renderablePhoto)
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

    /// Only the map keeps the classic card. Keyed off `activeSelection`, never
    /// `activeBackground`: while a map snapshot loads, the background reports Midnight,
    /// and deriving from it would flash the centered layout before the map lands. A
    /// *failed* map load is the other way around — the selection itself becomes the
    /// Midnight preset, which is centered on purpose. Without a route no background
    /// changes the answer: the route-less layout is the only one that fits.
    private var cardLayout: WorkoutShareCardLayout {
        guard hasRoute else { return .routeless }
        switch activeSelection {
        case .preset, .photo: return .centered
        case .map: return .classic
        }
    }

    /// Where the info block sits, for the preview and the export alike. Only a photo
    /// background is repositionable, and anything else reports the identity placement —
    /// so a preset, the map, or a Pro entitlement that lapses while a photo is still
    /// held can never render a transform the user isn't looking at.
    private var activeInfoTransform: WorkoutShareInfoTransform {
        guard activeSelection == .photo else { return .identity }
        // The in-flight value belongs to whichever step is wired to the gesture.
        let live = photoStep == .layout ? inFlightGesture : .idle
        return Self.merged(committedInfoTransform, with: live).clamped(cardSize: cardSize)
    }

    /// How the photo backdrop is framed, for the preview and the export alike. Only a
    /// photo background can be panned/zoomed; everything else reports the identity, so a
    /// preset, the map, or a lapsed entitlement can never render a framing the user
    /// isn't looking at.
    private var activePhotoTransform: WorkoutSharePhotoTransform {
        guard activeSelection == .photo, let photo = renderablePhoto else { return .identity }
        let live = photoStep == .photo ? inFlightGesture : .idle
        return Self.merged(photoTransform, with: live).clamped(imageSize: photo.size, cardSize: cardSize)
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
            routePoints: routePoints,
            route3D: route3D,
            dimension: activeDimension,
            locality: route?.locality,
            type: workout.type,
            background: activeBackground,
            layout: cardLayout,
            aspectRatio: activeAspectRatio,
            arrangement: activeArrangement,
            infoTransform: activeInfoTransform,
            photoTransform: activePhotoTransform,
            fontDesign: storedFontChoice.design,
            routeColor: storedRouteColorChoice.color(tint: workout.type.color)
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
                        .clamped(imageSize: selectedPhoto?.size ?? .zero, cardSize: cardSize)
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

                // Story-composer layering: the card fills the page, the rail floats over
                // its trailing edge, and the photo controls float over its bottom. No
                // ScrollView — the preview has to fit the cover's height, and a scroll
                // view's unbounded height would let the card size off the width alone
                // and run off the bottom.
                // The metrics strip sits under the card, not beside its icon, and takes
                // its room from the preview: a VStack lets the card shrink to fit above
                // it rather than the strip covering the card's own bottom edge.
                VStack(spacing: 12) {
                    cardPreview
                    if expandedOption == .metrics {
                        metricsTray
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(20)

                // The reader is only here for the tray's width budget; it draws nothing
                // itself, so the empty area around the rail stays untouchable.
                GeometryReader { proxy in
                    optionRail(availableWidth: proxy.size.width)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                }

                photoAdjustControls
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .photosPicker(isPresented: $isPickerPresented, selection: $photoItem, matching: .images)
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

                        Text("v1")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.blue.opacity(0.14), in: Capsule())
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button {
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
                BodyShareActivityView(image: payload.image) { self.payload = nil }
            }
            .alert(Text("Couldn't Load Photo"), isPresented: $showPhotoLoadError) {
                Button("OK", role: .cancel) {}
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
            // Keyed off photo mode itself, so every way in or out of it — a first pick, a
            // switch to a preset/map, a failed load, a lapsed entitlement — starts both
            // transforms from their default slot, at the first step.
            .onChange(of: activeSelection == .photo) { _, _ in
                resetPhotoAdjustments()
            }
            // And off the photo itself: replacing photo A with photo B never leaves
            // photo mode, so the mode key alone would keep A's framing under B.
            .onChange(of: selectedPhoto) { _, _ in
                resetPhotoAdjustments()
            }
            // A clamp is only valid for the card it was computed on: an offset that
            // parks the block near 16:9's edge would throw it off a 1:1 card entirely,
            // and the photo's overhang changes shape with the card too.
            .onChange(of: activeAspectRatio) { _, _ in
                resetPhotoAdjustments()
            }
            .task(id: photoItem) { await loadSelectedPhoto() }
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
                        cardView()
                            .frame(width: cardSize.width, height: cardSize.height)
                            .scaleEffect(previewScale, anchor: .topLeading)

                        if activeSelection == .photo {
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
                                    named: photoStep == .photo ? Text("Reset Photo") : Text("Reset Layout")
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
            // Outside photo mode nothing else wants a tap on the card, so this only
            // ever means "put the open tray away".
            .onTapGesture { closeTray() }
    }

    private func closeTray() {
        guard expandedOption != nil else { return }
        withAnimation(.snappy) { expandedOption = nil }
    }

    /// Over the card's bottom edge, always laid out and only shown in photo mode:
    /// appearing/disappearing would resize the preview — and so the gesture's scale
    /// divisor — the instant the user enters photo mode.
    private var photoAdjustControls: some View {
        let isPhotoMode = activeSelection == .photo
        return VStack(spacing: 8) {
            Text(photoStep == .photo
                 ? "Drag to move the photo. Pinch to zoom. Double-tap to reset."
                 : "Drag to move. Pinch to resize. Double-tap to reset.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Picker(selection: $photoStep) {
                    Text("Photo").tag(PhotoAdjustStep.photo)
                    Text("Layout").tag(PhotoAdjustStep.layout)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                // Laid out in both steps so switching doesn't change this row's height.
                Button {
                    withAnimation { photoStep = .layout }
                } label: {
                    Text("Next")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.blue, in: Capsule())
                }
                .buttonStyle(.plain)
                .opacity(photoStep == .photo ? 1 : 0)
                .disabled(photoStep != .photo)
                .accessibilityHidden(photoStep != .photo)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
        // Only enough shade to lift the controls off whatever photo is under them.
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .opacity(isPhotoMode ? 1 : 0)
        .disabled(!isPhotoMode)
        // The scrim is a real, hittable view: without this it would swallow taps meant
        // for the card in every other mode.
        .allowsHitTesting(isPhotoMode)
        .accessibilityHidden(!isPhotoMode)
    }

    private static let optionTileSize: CGFloat = 40
    private static let optionRowSpacing: CGFloat = 8
    /// Round rail buttons, big enough to be a comfortable target over the card.
    private static let railIconSize: CGFloat = 44
    private static let railPadding: CGFloat = 16
    /// Between a rail icon and its open tray.
    private static let railTrayGap: CGFloat = 12

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
            railRow(.font, symbol: "textformat", label: Text("Font"), trayWidth: trayWidth) {
                optionTiles {
                    ForEach(WorkoutShareFontChoice.allCases) { choice in
                        fontTile(choice)
                    }
                }
            }

            railRow(.ratio, symbol: "aspectratio", label: Text("Ratio"), trayWidth: trayWidth) {
                optionTiles {
                    ForEach(WorkoutShareAspectRatio.allCases) { ratio in
                        ratioTile(ratio)
                    }
                }
            }

            // Only a landscape card with a trace has two halves to split.
            if activeAspectRatio.isLandscape, hasRoute {
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

            railRow(
                .background,
                symbol: "photo.on.rectangle",
                label: Text("Background"),
                trayWidth: trayWidth
            ) {
                optionTiles {
                    ForEach(BodyWorkoutSharePreset.allCases) { preset in
                        presetSwatch(preset)
                    }
                    // Nothing to snapshot without a route, so the tile isn't offered.
                    if hasRoute {
                        mapTile()
                    }
                    photoTile()
                }
            }

            if hasRoute {
                railRow(.dimension, symbol: "move.3d", label: Text("3D"), trayWidth: trayWidth) {
                    dimensionTray
                }
            }

            // Last, and Pro-only — locked rather than hidden, so a free user still
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
        symbol: String,
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
                Image(systemName: symbol)
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

    /// Horizontal scroller shared by every tray — seven route colours don't fit beside
    /// the rail on a small phone, and a clipped row would hide options entirely. The
    /// trailing anchor keeps a short row of tiles hugging its icon (a scroll view
    /// otherwise pins content to the leading edge, leaving a gap beside the rail) and
    /// opens a long row on its last tiles, next to the icon that opened it. The Metrics
    /// tray overrides the anchor to `.leading`: its chips are the pool in card order, so
    /// a long row has to open on the first metric rather than the last.
    private func optionTiles<Content: View>(
        anchor: UnitPoint = .trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Self.optionRowSpacing) {
                content()
            }
            .padding(.vertical, 2)
        }
        .defaultScrollAnchor(anchor)
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

            Text("Pick 1 to 3 metrics.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        // Full-width strip under the card, so the scroller isn't sized by the rail's
        // tray budget and a tap between chips still reaches nothing behind it.
        .frame(maxWidth: .infinity)
    }

    /// One pickable metric. Unlike every other tray, a tap here doesn't close the tray:
    /// picking three metrics is three taps, and re-opening between each would make the
    /// bounds impossible to feel.
    private func metricChip(_ option: WorkoutShareMetricOption) -> some View {
        let ids = activeMetricIDs
        let isSelected = ids.contains(option.id)
        let isAtMaximum = ids.count >= WorkoutShareMetricSelection.maximumCount
        let isLastSelected = isSelected && ids.count == 1
        return Button {
            let next = WorkoutShareMetricSelection.toggling(
                option.id,
                in: ids,
                available: availableMetricOptions
            )
            guard next != ids else { return }
            storedMetricSelections = WorkoutShareMetricSelection.storing(
                next,
                for: workout.type,
                into: storedMetricSelections
            )
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
    /// fixed 20 pt long side so the five tiles read as one family of shapes.
    private func ratioTile(_ ratio: WorkoutShareAspectRatio) -> some View {
        let isSelected = activeAspectRatio == ratio
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
        let isSelected = activeDimension == dimension
        let isAvailable = dimension == .twoD || isThreeDAvailable
        let isLocked = dimension == .threeD && !isProUnlocked
        return Button {
            closeTray()
            guard !isLocked else {
                showBodyProPaywall = true
                return
            }
            storedDimension = dimension.rawValue
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

    private func selectionRing(isSelected: Bool) -> some View {
        Circle()
            .strokeBorder(
                Color.white.opacity(isSelected ? 0.9 : 0.3),
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
        let isSelected = activeSelection == .preset(preset)
        return Button {
            closeTray()
            storedBackground = BodyWorkoutShareBackgroundChoice.preset(preset).rawValue
            selectedPhoto = nil
            // Also reset the picker item so re-picking the same photo later re-fires
            // the `.task(id:)` load (an unchanged id would silently do nothing).
            photoItem = nil
        } label: {
            Circle()
                .fill(preset.gradient(tint: workout.type.color))
                .frame(width: Self.optionTileSize, height: Self.optionTileSize)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .overlay { selectionRing(isSelected: isSelected) }
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
            selectedPhoto = nil
            photoItem = nil
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
                if isLoadingPhoto {
                    Circle().fill(Color.black.opacity(0.35))
                    ProgressView()
                        .tint(.white)
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
    private var isBusy: Bool {
        isRendering || isSavingImage || isLoadingPhoto || (activeSelection == .map && activeMapSnapshot == nil)
    }

    @MainActor
    private func export() async {
        guard !isRendering else { return }
        isRendering = true
        defer { isRendering = false }

        if let image = renderCardImage() {
            payload = WorkoutSharePayload(image: image)
        } else {
            showRenderError = true
        }
    }

    /// Writes the card to the photo library with add-only access — never full-library
    /// read — so the prompt matches what saving actually needs.
    @MainActor
    private func saveToPhotos() async {
        guard !isSavingImage else { return }
        isSavingImage = true
        defer { isSavingImage = false }

        switch await Self.requestAddOnlyPhotoAccess() {
        case .authorized, .limited:
            break
        default:
            isPhotoAccessDenied = true
            showSaveError = true
            return
        }

        guard let image = renderCardImage() else {
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

        // Confirmation lives on the button itself; hold it just long enough to read,
        // then close the sheet — a successful save is this flow's natural end. On its
        // own task so `defer` re-enables both buttons right away.
        didSave = true
        Task {
            try? await Task.sleep(for: .seconds(1))
            dismiss()
        }
    }

    /// The one rasterization path Save and Share share: the card at its chosen point
    /// size, 3× (1080 px on the short side), forced dark and at `.large` dynamic type so
    /// the exported image never picks up the device's appearance or text-size settings.
    @MainActor
    private func renderCardImage() -> UIImage? {
        let renderer = ImageRenderer(
            content: cardView()
                .frame(width: cardSize.width, height: cardSize.height)
                .environment(\.colorScheme, .dark)
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
            // failing a photo returns to whatever was persisted.
            selectedPhoto = image
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

/// Wraps `UIActivityViewController` so the system share sheet can be presented via
/// `.sheet(item:)` — embedding it in a sheet also avoids the iPad popover-anchor crash.
private struct BodyShareActivityView: UIViewControllerRepresentable {
    let image: UIImage
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onComplete() }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
