//
//  BodyProfileView.swift
//  Body
//

import ImageIO
import PhotosUI
import SwiftUI
import UIKit

/// The pushed profile page: an avatar photo and a name, both stored on device only.
struct BodyProfileView: View {
    @AppStorage(BodyAppearancePreference.profileNameKey) private var profileName = ""
    @AppStorage(BodyAppearancePreference.profileAvatarDataKey) private var profileAvatarData = Data()
    @State private var photoItem: PhotosPickerItem?
    @State private var cropTarget: BodyProfileCropTarget?
    @State private var showingPhotoPicker = false

    private var avatarImage: UIImage? {
        profileAvatarData.isEmpty ? nil : UIImage(data: profileAvatarData)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    hero
                    nameField
                }
                .padding(.bottom, 12)

                privacyText
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 34)
            .readableContentColumn()
        }
        .background {
            Color.black.ignoresSafeArea()
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        // Latest-wins and cancellable: the picker can be re-opened before a slow
        // cloud photo finishes loading, and only the current pick may open the crop.
        .task(id: photoItem) { await loadPickedPhoto() }
        .fullScreenCover(item: $cropTarget) { target in
            BodyProfilePhotoCropView(
                image: target.image,
                onApply: { applyCroppedPhoto($0) },
                onCancel: { cropTarget = nil }
            )
        }
    }

    // Tap the avatar for a menu to choose, change, or delete the profile photo.
    private var hero: some View {
        ZStack {
            BodyProConfetti()

            Menu {
                Button {
                    showingPhotoPicker = true
                } label: {
                    // `LocalizedStringKey` explicitly: a ternary of string literals
                    // would otherwise pick Label's non-localizing `StringProtocol` init.
                    Label(
                        avatarImage == nil
                            ? LocalizedStringKey("Choose Photo")
                            : LocalizedStringKey("Change Photo"),
                        systemImage: "photo"
                    )
                }

                if avatarImage != nil {
                    Button(role: .destructive) {
                        profileAvatarData = Data()
                        playHaptic()
                    } label: {
                        Label("Delete Photo", systemImage: "trash")
                    }
                }
            } label: {
                heroAvatar
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 168)
        .padding(.top, 6)
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItem, matching: .images)
    }

    @ViewBuilder
    private var heroAvatar: some View {
        Group {
            if let avatarImage {
                Image(uiImage: avatarImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 116, height: 116)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.62),
                                    BodyProPalette.gold.opacity(0.18),
                                    .black.opacity(0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                    )
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 60, weight: .regular))
                    .foregroundColor(BodyProPalette.gold)
                    .frame(width: 116, height: 116)
                    .background(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(BodyProPalette.gold.opacity(0.14))
                    )
            }
        }
        .shadow(color: BodyProPalette.gold.opacity(0.22), radius: 22, x: 0, y: 15)
        .shadow(color: .black.opacity(0.18), radius: 6, x: 4, y: 8)
    }

    private var nameField: some View {
        TextField("Add a name", text: $profileName)
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .tint(BodyProPalette.gold)
            .lineLimit(1)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .frame(maxWidth: 260)
            .onChange(of: profileName) { _, newValue in
                if newValue.count > BodyUserProfile.maximumNameLength {
                    profileName = String(newValue.prefix(BodyUserProfile.maximumNameLength))
                }
            }
    }

    private var privacyText: some View {
        Text("Your name and photo are used only to personalize your workout share cards. Both are stored locally on this device and nothing is ever uploaded.")
            .font(.footnote)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
    }

    /// Decodes the picked photo off the main actor, then hands it to the crop step.
    private func loadPickedPhoto() async {
        guard let item = photoItem else { return }

        defer {
            // Only the pick that still owns the selection may clear it — a
            // superseded load must not cancel its successor's `task(id:)`.
            if photoItem == item {
                photoItem = nil
            }
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let image = try await Task.detached(priority: .userInitiated) {
                try BodyProfileImageCodec.downsampled(from: data)
            }.value
            try Task.checkCancellation()
            cropTarget = BodyProfileCropTarget(image: image)
        } catch {
            // A cancelled or undecodable pick simply leaves the current photo alone.
        }
    }

    private func applyCroppedPhoto(_ image: UIImage) {
        if let data = BodyProfileImageCodec.avatarData(from: image) {
            profileAvatarData = data
            playHaptic()
        }
        cropTarget = nil
    }

    private func playHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }
}

private struct BodyProfileCropTarget: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Pan/zoom rounded-square crop for the profile photo. Renders WYSIWYG via `ImageRenderer`.
private struct BodyProfilePhotoCropView: View {
    let image: UIImage
    let onApply: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let cropSize: CGFloat = 300

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 22) {
                    framedImage()
                        .clipShape(RoundedRectangle(cornerRadius: 82, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 82, style: .continuous)
                                .stroke(Color.white.opacity(0.6), lineWidth: 2)
                        )
                        .contentShape(Rectangle())
                        .gesture(combinedGesture)

                    Text("Pinch to zoom, drag to position.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            .navigationTitle("Adjust Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply", action: applyCrop)
                        .fontWeight(.bold)
                }
            }
        }
    }

    private func framedImage() -> some View {
        Color.clear
            .frame(width: cropSize, height: cropSize)
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(scale)
                    .offset(offset)
            }
    }

    private var combinedGesture: some Gesture {
        SimultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    scale = max(lastScale * value.magnification, 1)
                    // Zooming out shrinks the reachable pan range, so an offset
                    // that was legal at the old scale can expose a bare corner.
                    offset = clamped(offset)
                }
                .onEnded { _ in
                    lastScale = scale
                    lastOffset = offset
                },
            DragGesture()
                .onChanged { value in
                    offset = clamped(CGSize(width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height))
                }
                .onEnded { _ in lastOffset = offset }
        )
    }

    /// Keeps the scaled image covering the whole crop frame — the renderer would
    /// otherwise bake transparent edges into the avatar.
    private func clamped(_ proposed: CGSize) -> CGSize {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return .zero }

        // `scaledToFill` into the square frame, then the pinch scale on top.
        let fill = max(cropSize / size.width, cropSize / size.height) * scale
        let maxX = max((size.width * fill - cropSize) / 2, 0)
        let maxY = max((size.height * fill - cropSize) / 2, 0)

        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    @MainActor private func applyCrop() {
        let renderer = ImageRenderer(content: framedImage().clipped())
        renderer.scale = 2
        // No silent fallback: storing the uncropped original would ignore the
        // framing the user just chose, so keep the cover open instead.
        guard let cropped = renderer.uiImage else { return }
        onApply(cropped)
    }
}

/// Decode/encode for the profile avatar. Kept separate from the views so the
/// sizing rules are unit-testable.
enum BodyProfileImageCodec {
    enum CodecError: Error {
        case decodeFailed
    }

    /// The largest edge, in pixels, of the avatar written to `UserDefaults` —
    /// enough for the 116pt hero on a 3× display without upscaling, still only
    /// tens of KB as JPEG.
    static let avatarMaxDimension: CGFloat = 480

    /// Downscales with EXIF orientation baked in via `CGImageSource` thumbnailing —
    /// safe to call off the main actor so a large cloud photo never stalls the UI.
    nonisolated static func downsampled(from data: Data, maxPixelSize: Int = 2_048) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw CodecError.decodeFailed
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw CodecError.decodeFailed
        }
        return UIImage(cgImage: cgImage)
    }

    /// Aspect-fits into `maxDimension` (never upscaling) and encodes as JPEG.
    static func avatarData(from image: UIImage, maxDimension: CGFloat = avatarMaxDimension) -> Data? {
        // Work in pixels: the crop renderer hands back a 2× image whose `size` is
        // in points, and drawing that at its point size would halve its resolution.
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        guard size.width > 0, size.height > 0 else { return nil }

        let scale = min(maxDimension / size.width, maxDimension / size.height, 1)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        // Scale 1 so the stored JPEG really is `newSize` pixels on its longest edge.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: 0.85)
    }
}
