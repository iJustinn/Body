//
//  BodyWorkoutShareSheet.swift
//  Body
//
//  Preview-and-share flow for a workout's image. Presents the 360×640 card
//  scaled to fit, an options block (a free Font row, a free Route-colour row, and
//  the background strip: free gradient presets + a free route-map tile + a Pro-gated
//  photo tile, split into a 2D row and a Pro-gated 3D row), and Save/Share actions
//  that rasterize the card via `ImageRenderer` and hand the 1080×1920 image to the
//  photo library or the system share sheet. On a photo background the preview drives
//  two adjust steps: Photo pans/zooms the backdrop, Layout moves and resizes the card's
//  info block — both session-only, and both fed to the export so the image matches the
//  preview. The route is optional: a workout without one (indoor, strength, yoga…)
//  shares the same flow with the map tile and the 2D/3D rows dropped and the card's
//  route-less layout in place of the trace.
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

    @State private var selectedPhoto: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var isPickerPresented = false
    @State private var isLoadingPhoto = false
    /// One snapshot per dimension: 2D composites the flat route onto the roads, 3D the
    /// lifted ribbon, and the two are framed by different regions — so switching rows
    /// can't reuse the other's image, and neither is thrown away when the user switches
    /// back. Session-only, like the failure sets below.
    @State private var mapSnapshots: [WorkoutShareRouteDimension: UIImage] = [:]
    @State private var loadingMapDimensions: Set<WorkoutShareRouteDimension> = []
    /// A snapshot failure is session-only: the stored choice stays `.map`, so a
    /// transient failure (offline, say) doesn't discard the user's background — the
    /// next open retries it — while this sheet shows Midnight in the meantime.
    @State private var failedMapDimensions: Set<WorkoutShareRouteDimension> = []
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
    private let metrics: [WorkoutShareMetric]
    private let centeredMetrics: [WorkoutShareMetric]
    private let routePoints: [CGPoint]?
    /// The elevation ribbon at rest (yaw 0) — `nil` when the route can't carry one, which
    /// is also what makes the 3D row unavailable.
    private let route3D: WorkoutRoute3DProjection.Projected3D?

    private enum PhotoAdjustStep: Hashable {
        case photo
        case layout
    }

    init(workout: WorkoutSummary, route: WorkoutRoute?, presentation: WorkoutDetailPresentation) {
        self.workout = workout
        self.route = route
        self.presentation = presentation
        // A route-less workout only ever draws the block layout, and draws it from its
        // own, longer selection — the classic row is unreachable, so it stays empty.
        self.metrics = route == nil ? [] : WorkoutShareMetricsBuilder.metrics(for: presentation, type: workout.type)
        self.centeredMetrics = route == nil
            ? WorkoutShareMetricsBuilder.routelessMetrics(for: presentation, type: workout.type)
            : WorkoutShareMetricsBuilder.centeredMetrics(for: presentation, type: workout.type)
        self.routePoints = route.flatMap { WorkoutShareRouteProjection.normalizedPoints(for: $0.coordinates) }
        self.route3D = route.flatMap { WorkoutRoute3DProjection.projected(for: $0.coordinates) }
    }

    private var isProUnlocked: Bool { proStore?.isPro == true }

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

    private var storedFontChoice: WorkoutShareFontChoice {
        WorkoutShareFontChoice.stored(rawValue: storedFont)
    }

    private var storedRouteColorChoice: WorkoutShareRouteColorChoice {
        WorkoutShareRouteColorChoice.stored(rawValue: storedRouteColor)
    }

    /// The snapshot for the dimension on screen; the other row's cached image never
    /// stands in for it.
    private var activeMapSnapshot: UIImage? { mapSnapshots[activeDimension] }

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
        // Stored choice is the map, but this session couldn't snapshot the dimension
        // on screen. The other dimension's failure doesn't count — it has its own row.
        if failedMapDimensions.contains(activeDimension) { return .preset(.midnight) }
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
        return Self.merged(committedInfoTransform, with: live).clamped()
    }

    /// How the photo backdrop is framed, for the preview and the export alike. Only a
    /// photo background can be panned/zoomed; everything else reports the identity, so a
    /// preset, the map, or a lapsed entitlement can never render a framing the user
    /// isn't looking at.
    private var activePhotoTransform: WorkoutSharePhotoTransform {
        guard activeSelection == .photo, let photo = renderablePhoto else { return .identity }
        let live = photoStep == .photo ? inFlightGesture : .idle
        return Self.merged(photoTransform, with: live).clamped(imageSize: photo.size)
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
        BodyWorkoutShareCardView(
            presentation: presentation,
            metrics: metrics,
            centeredMetrics: centeredMetrics,
            routePoints: routePoints,
            route3D: route3D,
            dimension: activeDimension,
            locality: route?.locality,
            type: workout.type,
            background: activeBackground,
            layout: cardLayout,
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
                        .clamped(imageSize: selectedPhoto?.size ?? .zero)
                case .layout:
                    committedInfoTransform = Self.merged(committedInfoTransform, with: gesture).clamped()
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

                // No ScrollView: the preview has to fit the cover's height, and a
                // scroll view's unbounded height would let the 9:16 box size off the
                // width alone and run off the bottom.
                VStack(spacing: 28) {
                    VStack(spacing: 10) {
                        cardPreview
                        photoAdjustControls
                    }
                    .frame(maxHeight: .infinity)
                    backgroundSection
                }
                .padding(20)
            }
            // The title stays set for accessibility/back-button inheritance; the
            // principal item is what actually draws, so the beta badge can sit beside it.
            .navigationTitle(Text("Share"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Text("Share")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("Beta v2")
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
            .task(id: photoItem) { await loadSelectedPhoto() }
            // Opens on the map without waiting for a tap, and re-fires whenever the
            // dimension on screen changes — so a Pro lapse (3D → 2D) or a restore
            // (2D → 3D) loads the newly active row's snapshot on its own.
            .task(id: MapLoadKey(isMapActive: activeSelection == .map, dimension: activeDimension)) {
                let dimension = activeDimension
                guard activeSelection == .map,
                      mapSnapshots[dimension] == nil,
                      !loadingMapDimensions.contains(dimension),
                      !failedMapDimensions.contains(dimension) else { return }
                await loadMapSnapshot(dimension: dimension, isUserInitiated: false)
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
        // A clear box with the card's 9:16 aspect ratio establishes the layout size;
        // the overlay scales the fixed 360-wide card to whatever width is available.
        Color.clear
            .aspectRatio(360.0 / 640.0, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    let previewScale = proxy.size.width / 360
                    // Top-leading, not centered: in photo mode the gesture layer grows
                    // this stack to the proxy size, and centering would inset the fixed
                    // 360×640 card before the top-leading scale — on an iPad-width
                    // preview that shows as blank space plus a clipped right/bottom edge.
                    ZStack(alignment: .topLeading) {
                        cardView()
                            .frame(width: 360, height: 640)
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
    }

    /// Under the preview, always laid out and only shown in photo mode: appearing/
    /// disappearing would resize the preview — and so the gesture's scale divisor — the
    /// instant the user enters photo mode.
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
        .opacity(isPhotoMode ? 1 : 0)
        .disabled(!isPhotoMode)
        .accessibilityHidden(!isPhotoMode)
    }

    /// Font, route colour, and the background rows. Everything here is free except the
    /// 3D background row, which carries the Pro gate.
    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: Self.optionRowSpacing) {
            fontRow
            // The card draws no trace of its own without a route, so there is nothing
            // for a colour to apply to.
            if hasRoute {
                routeColorRow
            }

            Text("Background")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.75))

            if hasRoute {
                backgroundRow(for: .twoD)
                backgroundRow(for: .threeD)
                if !isThreeDAvailable {
                    Text("3D needs a route with elevation data.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
            } else {
                // One unlabelled row: without a route there is no second dimension to
                // tell it apart from.
                backgroundTiles(dimension: .twoD)
            }
        }
        .photosPicker(isPresented: $isPickerPresented, selection: $photoItem, matching: .images)
        .sheet(isPresented: $showBodyProPaywall) {
            NavigationStack { BodyProView() }
        }
    }

    /// Tile diameter and row spacing are small on purpose: five rows have to fit under
    /// the preview on a 375×667 phone without pushing the card off the bottom.
    private static let optionTileSize: CGFloat = 40
    private static let optionRowSpacing: CGFloat = 8
    private static let optionRowLabelWidth: CGFloat = 44

    private func optionRow<Content: View>(_ label: Text, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: Self.optionRowSpacing) {
            label
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
                .frame(width: Self.optionRowLabelWidth, alignment: .leading)
            content()
        }
    }

    /// Horizontal scroller shared by every tile row — seven route colours don't fit on a
    /// small phone, and a clipped row would hide options entirely.
    private func optionTiles<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Self.optionRowSpacing) {
                content()
            }
            .padding(.vertical, 2)
        }
    }

    private var fontRow: some View {
        optionRow(Text("Font")) {
            optionTiles {
                ForEach(WorkoutShareFontChoice.allCases) { choice in
                    fontTile(choice)
                }
            }
        }
    }

    /// Ring-only selection, no checkmark: the point of the tile is the "Aa" specimen,
    /// and a glyph on top of it would hide the very thing being picked.
    private func fontTile(_ choice: WorkoutShareFontChoice) -> some View {
        let isSelected = storedFontChoice == choice
        return Button {
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

    /// Colour of the trace the card draws itself. The map background composites its own
    /// pace-coloured route, so the row is disabled while Map is the active background.
    private var routeColorRow: some View {
        let appliesToBackground = activeSelection != .map
        return optionRow(Text("Route")) {
            optionTiles {
                ForEach(WorkoutShareRouteColorChoice.allCases) { choice in
                    routeColorTile(choice)
                }
            }
        }
        .opacity(appliesToBackground ? 1 : 0.4)
        .disabled(!appliesToBackground)
        .accessibilityHint(
            appliesToBackground
            ? Text(verbatim: "")
            : Text("Route color doesn't apply to the Map background.")
        )
    }

    private func routeColorTile(_ choice: WorkoutShareRouteColorChoice) -> some View {
        let isSelected = storedRouteColorChoice == choice
        return Button {
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

    /// One labelled background row per dimension. The 3D row is Pro-gated (lock badges
    /// on every tile, taps open the paywall) and greyed out entirely when the route has
    /// no usable altitude.
    private func backgroundRow(for dimension: WorkoutShareRouteDimension) -> some View {
        let isAvailable = dimension == .twoD || isThreeDAvailable
        return optionRow(dimension == .twoD ? Text("2D") : Text("3D")) {
            backgroundTiles(dimension: dimension)
        }
        .opacity(isAvailable ? 1 : 0.4)
        .disabled(!isAvailable)
        .accessibilityHint(
            isAvailable ? Text(verbatim: "") : Text("3D needs a route with elevation data.")
        )
    }

    private func backgroundTiles(dimension: WorkoutShareRouteDimension) -> some View {
        optionTiles {
            ForEach(BodyWorkoutSharePreset.allCases) { preset in
                presetSwatch(preset, dimension: dimension)
            }
            // Nothing to snapshot without a route, so the tile isn't offered.
            if hasRoute {
                mapTile(dimension: dimension)
            }
            photoTile(dimension: dimension)
        }
    }

    /// The 3D rows are Pro-only. Returns `false` when the tap was spent on the paywall,
    /// so the caller leaves every other piece of state alone.
    private func claimDimension(_ dimension: WorkoutShareRouteDimension) -> Bool {
        if dimension == .threeD, !isProUnlocked {
            showBodyProPaywall = true
            return false
        }
        storedDimension = dimension.rawValue
        return true
    }

    private func selectionRing(isSelected: Bool) -> some View {
        Circle()
            .strokeBorder(
                Color.white.opacity(isSelected ? 0.9 : 0.3),
                lineWidth: isSelected ? 2 : 1
            )
    }

    /// The Pro badge the 3D tiles carry for a non-Pro user, and the photo tile always has.
    private var lockBadge: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(4)
            .background(Color.black.opacity(0.55), in: Circle())
    }

    @ViewBuilder
    private func dimensionLockBadge(_ dimension: WorkoutShareRouteDimension) -> some View {
        if dimension == .threeD, !isProUnlocked {
            lockBadge
        }
    }

    private func presetSwatch(_ preset: BodyWorkoutSharePreset, dimension: WorkoutShareRouteDimension) -> some View {
        // A tile only reads as selected on the row whose dimension is actually drawing.
        let isSelected = activeSelection == .preset(preset) && dimension == activeDimension
        return Button {
            guard claimDimension(dimension) else { return }
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
                .overlay(alignment: .bottomTrailing) { dimensionLockBadge(dimension) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.localizedName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Free route-map background: a dark map snapshot with the pace-colored route
    /// composited in, generated once per dimension on first selection.
    private func mapTile(dimension: WorkoutShareRouteDimension) -> some View {
        let isSelected = activeSelection == .map && dimension == activeDimension
        let snapshot = mapSnapshots[dimension]
        return Button {
            guard claimDimension(dimension) else { return }
            selectedPhoto = nil
            photoItem = nil
            storedBackground = BodyWorkoutShareBackgroundChoice.map.rawValue
            // Tapping Map is also how the user retries this dimension after a failure.
            failedMapDimensions.remove(dimension)
            if mapSnapshots[dimension] == nil, !loadingMapDimensions.contains(dimension) {
                Task { await loadMapSnapshot(dimension: dimension, isUserInitiated: true) }
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
                if loadingMapDimensions.contains(dimension) {
                    Circle().fill(Color.black.opacity(0.35))
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(width: Self.optionTileSize, height: Self.optionTileSize)
            .clipShape(Circle())
            .overlay { selectionRing(isSelected: isSelected) }
            .overlay(alignment: .bottomTrailing) { dimensionLockBadge(dimension) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Map"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func photoTile(dimension: WorkoutShareRouteDimension) -> some View {
        let isSelected = isPhotoActive && dimension == activeDimension
        return Button {
            guard isProUnlocked else {
                showBodyProPaywall = true
                return
            }
            guard claimDimension(dimension) else { return }
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

    /// The one rasterization path Save and Share share: the 360×640 card at 3×
    /// (1080×1920), forced dark and at `.large` dynamic type so the exported image
    /// never picks up the device's appearance or text-size settings.
    @MainActor
    private func renderCardImage() -> UIImage? {
        let renderer = ImageRenderer(
            content: cardView()
                .frame(width: 360, height: 640)
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
    private func loadMapSnapshot(dimension: WorkoutShareRouteDimension, isUserInitiated: Bool) async {
        // Before the flag, not after: a route-less sheet has no map to load, and
        // flipping the loading flag for a call that can't finish one would be enough
        // to leave Save/Share disabled.
        guard let route else { return }
        loadingMapDimensions.insert(dimension)
        defer { loadingMapDimensions.remove(dimension) }

        if let image = await Self.mapBackground(for: route, tint: UIColor(workout.type.color), dimension: dimension) {
            // Cache even if the user switched away meanwhile — re-selecting this row
            // then shows the snapshot instantly.
            mapSnapshots[dimension] = image
        } else {
            // Read the selection before recording the failure: recording it is what
            // makes `activeSelection` fall back to Midnight.
            let isStillRequested = activeSelection == .map && activeDimension == dimension
            // Recorded whatever the user is looking at now, so the opening task won't
            // retry a dimension that just failed — the Map tile clears it to retry.
            failedMapDimensions.insert(dimension)
            // Only alert while this dimension is still what's on screen and the user
            // asked for it: a stale error over a row they already left is noise, and
            // the sheet's own opening load must not alert on every unsnapshottable route.
            if isStillRequested, isUserInitiated {
                showMapLoadError = true
            }
        }
    }

    /// Full-card (360×640 pt at 3×) dark map snapshot with the pace-colored route
    /// composited in via the route hero's drawing. Internal so the sample renderer
    /// and tests can produce the exact export background.
    ///
    /// - Parameter dimension: `.threeD` raises the route off the roads as a 2.5D ribbon
    ///   and frames the region with headroom above it for the lifted line.
    @MainActor
    static func mapBackground(
        for route: WorkoutRoute,
        tint: UIColor,
        dimension: WorkoutShareRouteDimension
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

        let options = MKMapSnapshotter.Options()
        options.region = mapRegion(for: coordinates, liftFraction: lift?.max() ?? 0)
        options.size = CGSize(width: 360, height: 640)
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
    /// between the top (280 pt) and bottom (210 pt) map scrims of the 640 pt card.
    /// The route's northmost/southmost points bound onto that band's edges and its
    /// center sits at the band's center, so the trace never runs under the shaded
    /// header or metrics areas.
    ///
    /// - Parameter liftFraction: The 3D ribbon's tallest lift, in ground spans (0 for a
    ///   flat route). The ribbon stands straight up on screen, so the region grows by
    ///   that much on the north side and the lifted line clears the header scrim.
    private static func mapRegion(
        for coordinates: [CLLocationCoordinate2D],
        liftFraction: Double
    ) -> MKCoordinateRegion {
        let cardWidth = 360.0, cardHeight = 640.0
        let bandTop = 280.0, bandBottom = cardHeight - 210.0
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
        // width so wide routes never clip horizontally.
        let visibleLatSpan = max(
            paddedLatSpan * cardHeight / (bandHeight * 2.0),
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
/// switching to or from Map, or the dimension on screen flipping under a Pro lapse or
/// restore — restarts the task against the newly needed image.
private struct MapLoadKey: Equatable {
    let isMapActive: Bool
    let dimension: WorkoutShareRouteDimension
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
