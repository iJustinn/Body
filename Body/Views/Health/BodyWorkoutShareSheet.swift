//
//  BodyWorkoutShareSheet.swift
//  Body
//
//  Preview-and-share flow for a workout's route image. Presents the 360×640 card
//  scaled to fit, a background strip (free gradient presets + a free route-map
//  tile + a Pro-gated photo tile), and Save/Share actions that rasterize the card
//  via `ImageRenderer` and hand the 1080×1920 image to the photo library or the
//  system share sheet.
//

import SwiftUI
import PhotosUI
import Photos
import ImageIO
import MapKit
import UIKit

struct BodyWorkoutShareSheet: View {
    let workout: WorkoutSummary
    let route: WorkoutRoute
    let presentation: WorkoutDetailPresentation

    @Environment(BodyProStore.self) private var proStore: BodyProStore?

    @AppStorage(BodyWorkoutShareBackgroundChoice.storageKey) private var storedBackground: String =
        BodyWorkoutShareBackgroundChoice.map.rawValue

    @State private var selectedPhoto: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var isPickerPresented = false
    @State private var isLoadingPhoto = false
    @State private var mapSnapshot: UIImage?
    @State private var isLoadingMap = false
    /// A snapshot failure is session-only: the stored choice stays `.map`, so a
    /// transient failure (offline, say) doesn't discard the user's background — the
    /// next open retries it — while this sheet shows Midnight in the meantime.
    @State private var mapSnapshotFailed = false
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

    /// Computed once from the shared presentation so the card's values never drift
    /// from the detail page and the projection isn't redone on every body pass.
    private let metrics: [WorkoutShareMetric]
    private let routePoints: [CGPoint]?

    init(workout: WorkoutSummary, route: WorkoutRoute, presentation: WorkoutDetailPresentation) {
        self.workout = workout
        self.route = route
        self.presentation = presentation
        self.metrics = WorkoutShareMetricsBuilder.metrics(for: presentation, type: workout.type)
        self.routePoints = WorkoutShareRouteProjection.normalizedPoints(for: route.coordinates)
    }

    private var isProUnlocked: Bool { proStore?.isPro == true }

    /// What the sheet restores on open — the map unless a preset was last picked.
    private var selectedChoice: BodyWorkoutShareBackgroundChoice {
        BodyWorkoutShareBackgroundChoice.stored(rawValue: storedBackground)
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

    private var activeSelection: ActiveSelection {
        if renderablePhoto != nil { return .photo }
        if case .preset(let preset) = selectedChoice { return .preset(preset) }
        // Stored choice is the map, but this session couldn't snapshot it.
        if mapSnapshotFailed { return .preset(.midnight) }
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
        if let mapSnapshot {
            return .map(mapSnapshot)
        }
        // The map is active but hasn't snapshotted yet, and there's no "last preset"
        // to fall back to — Midnight is the same visual the load state always showed.
        return .preset(.midnight)
    }

    private func cardView() -> BodyWorkoutShareCardView {
        BodyWorkoutShareCardView(
            presentation: presentation,
            metrics: metrics,
            routePoints: routePoints,
            locality: route.locality,
            type: workout.type,
            background: activeBackground
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backdrop

                ScrollView {
                    VStack(spacing: 28) {
                        cardPreview
                        backgroundSection
                    }
                    .padding(20)
                }
            }
            .navigationTitle(Text("Share Workout"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { shareBar }
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
            .task(id: photoItem) { await loadSelectedPhoto() }
            .task {
                // Open on the map without waiting for a tap. Same guards as the map
                // tile's action so a tap and this task can't both start a load.
                if activeSelection == .map, mapSnapshot == nil, !isLoadingMap {
                    await loadMapSnapshot(isUserInitiated: false)
                }
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
                    cardView()
                        .frame(width: 360, height: 640)
                        .scaleEffect(proxy.size.width / 360, anchor: .topLeading)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
    }

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Background")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.75))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(BodyWorkoutSharePreset.allCases) { preset in
                        presetSwatch(preset)
                    }
                    mapTile
                    photoTile
                }
                .padding(.vertical, 2)
            }
        }
        .photosPicker(isPresented: $isPickerPresented, selection: $photoItem, matching: .images)
        .sheet(isPresented: $showBodyProPaywall) {
            NavigationStack { BodyProView() }
        }
    }

    private func presetSwatch(_ preset: BodyWorkoutSharePreset) -> some View {
        let isSelected = activeSelection == .preset(preset)
        return Button {
            storedBackground = BodyWorkoutShareBackgroundChoice.preset(preset).rawValue
            selectedPhoto = nil
            // Also reset the picker item so re-picking the same photo later re-fires
            // the `.task(id:)` load (an unchanged id would silently do nothing).
            photoItem = nil
        } label: {
            Circle()
                .fill(preset.gradient(tint: workout.type.color))
                .frame(width: 44, height: 44)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .overlay {
                    Circle()
                        .strokeBorder(
                            Color.white.opacity(isSelected ? 0.9 : 0.15),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.localizedName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Free route-map background: a dark map snapshot with the pace-colored route
    /// composited in, generated once on first selection.
    private var mapTile: some View {
        let isSelected = activeSelection == .map
        return Button {
            selectedPhoto = nil
            photoItem = nil
            storedBackground = BodyWorkoutShareBackgroundChoice.map.rawValue
            // Tapping Map is also how the user retries after a failed load.
            mapSnapshotFailed = false
            if mapSnapshot == nil, !isLoadingMap {
                Task { await loadMapSnapshot(isUserInitiated: true) }
            }
        } label: {
            ZStack {
                if let mapSnapshot {
                    Image(uiImage: mapSnapshot)
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle().fill(Color.white.opacity(0.1))
                    Image(systemName: "map")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                if isLoadingMap {
                    Circle().fill(Color.black.opacity(0.35))
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(
                        Color.white.opacity(isSelected ? 0.9 : 0.15),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Map"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var photoTile: some View {
        Button {
            if isProUnlocked {
                isPickerPresented = true
            } else {
                showBodyProPaywall = true
            }
        } label: {
            ZStack {
                if let selectedPhoto {
                    Image(uiImage: selectedPhoto)
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle().fill(Color.white.opacity(0.1))
                    Image(systemName: "photo")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                if isLoadingPhoto {
                    Circle().fill(Color.black.opacity(0.35))
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(
                        Color.white.opacity(isPhotoActive ? 0.9 : 0.15),
                        lineWidth: isPhotoActive ? 2 : 1
                    )
            }
            .overlay(alignment: .bottomTrailing) {
                if !isProUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Color.black.opacity(0.55), in: Circle())
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Your Photo"))
        .accessibilityAddTraits(isPhotoActive ? [.isSelected] : [])
    }

    private var shareBar: some View {
        HStack(spacing: 12) {
            Button {
                Task { await export() }
            } label: {
                HStack(spacing: 8) {
                    if isRendering {
                        ProgressView().tint(.white)
                    }
                    Text("Share")
                }
                .modifier(ShareActionChrome(tint: workout.type.color))
            }
            .buttonStyle(.plain)
            .disabled(isBusy)

            Button {
                Task { await saveToPhotos() }
            } label: {
                HStack(spacing: 8) {
                    if didSave {
                        Image(systemName: "checkmark")
                        Text("Saved")
                    } else {
                        if isSavingImage {
                            ProgressView().tint(.white)
                        }
                        Text("Save")
                    }
                }
                .modifier(ShareActionChrome(tint: workout.type.color))
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    /// Also busy while the *active* background is still loading — rendering then would
    /// silently rasterize the previous/preset background instead. A map load abandoned
    /// for a preset/photo doesn't hold the buttons hostage.
    private var isBusy: Bool {
        isRendering || isSavingImage || isLoadingPhoto || (activeSelection == .map && isLoadingMap)
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

        // Confirmation lives on the button itself; revert on its own task so `defer`
        // can re-enable both buttons right away.
        didSave = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didSave = false
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
    private func loadMapSnapshot(isUserInitiated: Bool) async {
        isLoadingMap = true
        defer { isLoadingMap = false }

        if let image = await Self.mapBackground(for: route, tint: UIColor(workout.type.color)) {
            // Cache even if the user switched away meanwhile — re-selecting Map
            // then shows the snapshot instantly.
            mapSnapshot = image
        } else if activeSelection == .map {
            // Only fall back while Map is still the active selection; a stale error
            // over a preset/photo the user already moved to is noise. And only alert
            // if they asked for the map — the sheet's own opening load must not put
            // an alert over every open of a route that can't snapshot.
            mapSnapshotFailed = true
            if isUserInitiated {
                showMapLoadError = true
            }
        }
    }

    /// Full-card (360×640 pt at 3×) dark map snapshot with the pace-colored route
    /// composited in via the route hero's drawing. Internal so the sample renderer
    /// and tests can produce the exact export background.
    @MainActor
    static func mapBackground(for route: WorkoutRoute, tint: UIColor) async -> UIImage? {
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

        let options = MKMapSnapshotter.Options()
        options.region = mapRegion(for: coordinates)
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
        return BodyWorkoutRouteMapHero.draw(route: validCoordinates, on: result, fallbackTint: tint)
    }

    /// Region placing the route inside the card's no-fading band — the clear area
    /// between the top (280 pt) and bottom (210 pt) map scrims of the 640 pt card.
    /// The route's northmost/southmost points bound onto that band's edges and its
    /// center sits at the band's center, so the trace never runs under the shaded
    /// header or metrics areas.
    private static func mapRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
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

        // Visible latitude span: the route renders ~2× the band height (centered
        // near the band, extending into the scrims' faded edges — full-band-only
        // read as too small), while its longitude extent stays within ~92% of the
        // width so wide routes never clip horizontally.
        let visibleLatSpan = max(
            routeLatSpan * cardHeight / (bandHeight * 2.0),
            routeLonSpanAdjusted / 0.92 * cardHeight / cardWidth
        )

        // Shift the map center north of the route center so the route's center lands
        // slightly below the band's center (below the card's midline; screen y grows
        // southward) — nudged down to sit clear of the taller header shade.
        let routeCenterY = bandCenterY + 20
        let centerLatitude = midLatitude + (routeCenterY - cardHeight / 2) / cardHeight * visibleLatSpan

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

/// The chrome both share-bar actions share: a flat translucent fill of the workout
/// type's color under a thin white rim — deliberately flat (no gradient, material
/// blur, or specular sheen) to match the app's glass language.
private struct ShareActionChrome: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        content
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(tint.opacity(0.85), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            }
    }
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
