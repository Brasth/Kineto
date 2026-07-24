import AppKit
import CryptoKit
import Foundation
import ImageIO
import SwiftUI

extension FloatingCaptionPetState {
    var isPanelDragEligible: Bool {
        self != .hidden
    }
}

enum PetDexSpriteFrameLoader {
    private static let idleFrameCount = 6

    static func idleFrames(for pet: PetDexInstalledPet) throws -> [NSImage] {
        let data = try Data(contentsOf: try selectedSpriteURL(for: pet))
        return try idleFrames(data: data, pet: pet)
    }

    static func idleFrames(data: Data, pet: PetDexInstalledPet) throws -> [NSImage] {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == pet.spriteSHA256 else {
            throw SpriteError.invalidAsset
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw SpriteError.invalidAsset
        }

        let rowCount = pet.layout == .classic8x9 ? 9 : 11
        guard sheet.width == pet.pixelWidth,
              sheet.height == pet.pixelHeight,
              sheet.width % 8 == 0,
              sheet.height % rowCount == 0
        else {
            throw SpriteError.invalidAsset
        }

        let frameWidth = sheet.width / 8
        let frameHeight = sheet.height / rowCount
        return try (0..<idleFrameCount).map { column in
            guard let frame = sheet.cropping(
                to: CGRect(
                    x: column * frameWidth,
                    y: 0,
                    width: frameWidth,
                    height: frameHeight
                )
            ) else {
                throw SpriteError.invalidAsset
            }
            return NSImage(
                cgImage: frame,
                size: NSSize(width: frameWidth, height: frameHeight)
            )
        }
    }

    private static func selectedSpriteURL(for pet: PetDexInstalledPet) throws -> URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw SpriteError.invalidAsset
        }
        return applicationSupport
            .appending(path: "Kineto", directoryHint: .isDirectory)
            .appending(path: "Pets", directoryHint: .isDirectory)
            .appending(path: "Selected", directoryHint: .isDirectory)
            .appending(path: pet.spriteFilename)
    }

    private enum SpriteError: Error {
        case invalidAsset
    }
}
final class PetDexSpriteFrames: @unchecked Sendable {
    let images: [NSImage]

    init(images: [NSImage]) {
        self.images = images
    }
}

struct FloatingCaptionPetView: View {
    let state: FloatingCaptionPetState
    let visualPreferences: FloatingCaptionPetVisualPreferences
    let onAssetInvalidated: (String) -> Void
    let onPanelDragChanged: (CGSize) -> Void
    let onPanelDragEnded: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frames: [NSImage] = []
    @State private var animationStart = Date()
    @State private var invalidatedPetID: String?

    init(
        state: FloatingCaptionPetState,
        visualPreferences: FloatingCaptionPetVisualPreferences,
        onAssetInvalidated: @escaping (String) -> Void = { _ in },
        onPanelDragChanged: @escaping (CGSize) -> Void = { _ in },
        onPanelDragEnded: @escaping () -> Void = {}
    ) {
        self.state = state
        self.visualPreferences = visualPreferences
        self.onAssetInvalidated = onAssetInvalidated
        self.onPanelDragChanged = onPanelDragChanged
        self.onPanelDragEnded = onPanelDragEnded
    }

    var body: some View {
        renderedSprite
            .frame(
                width: visualPreferences.size.points,
                height: visualPreferences.size.points
            )
            .opacity(state == .hidden ? 0 : 1)
            .offset(y: state == .hidden ? -8 : 0)
            .animation(.easeOut(duration: 0.2), value: state)
            .contentShape(Rectangle().scale(2.2))
            .allowsHitTesting(state.isPanelDragEligible)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onPanelDragChanged($0.translation) }
                    .onEnded { _ in onPanelDragEnded() }
            )
            .accessibilityHidden(true)
            .task(id: visualPreferences.pet.id) {
                await loadFrames()
            }
    }

    @ViewBuilder
    private var renderedSprite: some View {
        if effectiveMotion == .subtle {
            TimelineView(.periodic(from: .now, by: 1.1 / 6)) { context in
                frameView(index: subtleFrameIndex(at: context.date))
            }
        } else {
            frameView(index: 0)
        }
    }

    @ViewBuilder
    private func frameView(index: Int) -> some View {
        if frames.indices.contains(index) {
            Image(nsImage: frames[index])
                .resizable()
                .interpolation(.none)
                .scaledToFit()
        } else {
            Color.clear
        }
    }

    private func subtleFrameIndex(at date: Date) -> Int {
        guard !frames.isEmpty else { return 0 }
        let elapsed = max(0, date.timeIntervalSince(animationStart))
        return Int(elapsed / (1.1 / 6)).quotientAndRemainder(dividingBy: 6).remainder
    }

    private var effectiveMotion: FloatingCaptionPetMotion {
        visualPreferences.motion.effective(reduceMotion: reduceMotion)
    }

    @MainActor
    private func loadFrames() async {
        frames = []
        invalidatedPetID = nil
        let pet = visualPreferences.pet

        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                PetDexSpriteFrames(
                    images: try PetDexSpriteFrameLoader.idleFrames(for: pet)
                )
            }.value
            guard pet.id == visualPreferences.pet.id else { return }
            frames = loaded.images
            animationStart = .now
        } catch {
            guard invalidatedPetID != pet.id else { return }
            invalidatedPetID = pet.id
            onAssetInvalidated(pet.id)
        }
    }
}
