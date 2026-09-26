// Copyright 2026 Stefan Radermacher
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import AppKit
import AVFoundation
import ImageIO
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// Thumbnails of images and videos, kept in memory only. Motiv makes them itself, see `Stills`,
/// so that no copy of the pictures stays behind on disk.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.totalCostLimit = 400 * 1024 * 1024
    }

    /// Thumbnails come in a few fixed pixel sizes, so that resizing the grid reuses them.
    static func pixelSize(for points: CGFloat, scale: CGFloat) -> Int {
        let needed = points * scale
        return [128, 256, 512, 1024].first { CGFloat($0) >= needed } ?? 1024
    }

    func cached(_ url: URL, pixels: Int) -> NSImage? {
        cache.object(forKey: key(url, pixels))
    }

    /// As many at a time as the Mac has cores; very large pictures one after the other, since a
    /// folder of them would otherwise need gigabytes at once.
    private static let limiter = Limiter(limit: max(2, ProcessInfo.processInfo.activeProcessorCount))
    private static let largeLimiter = Limiter(limit: 1)

    /// nil if the cell asking for it went away while waiting.
    func thumbnail(for url: URL, pixels: Int) async -> NSImage? {
        if let image = cached(url, pixels: pixels) { return image }
        let limiter = Stills.isLarge(url) ? Self.largeLimiter : Self.limiter
        await limiter.acquire()
        defer { Task { await limiter.release() } }
        // Scrolled past while waiting: not needed any more.
        guard !Task.isCancelled else { return nil }
        if let image = cached(url, pixels: pixels) { return image }
        let image = await Stills.thumbnail(of: url, pixels: pixels).map { NSImage(cgImage: $0, size: CGSize(width: $0.width, height: $0.height)) }
            ?? NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(image, forKey: key(url, pixels), cost: pixels * pixels * 4)
        return image
    }

    private func key(_ url: URL, _ pixels: Int) -> NSString {
        "\(pixels)|\(url.path)" as NSString
    }
}

/// A thumbnail that loads itself. At most `size` points wide and high, keeping its aspect ratio.
/// Pictures that may be sensitive appear blurred, see SensitiveContentGuard; until they have been
/// checked, only the placeholder shows.
struct ThumbnailImage: View {
    let url: URL
    let size: CGFloat
    var isVideo = false

    @Environment(\.displayScale) private var displayScale
    @State private var image: NSImage?

    private var guardian: SensitiveContentGuard { .shared }

    var body: some View {
        let pixels = ThumbnailCache.pixelSize(for: size, scale: displayScale)
        let concealed = guardian.isConcealed(url)
        Group {
            if let image, concealed == true, guardian.isStrict {
                // For a child a plain area in the picture's proportions, nothing of the picture.
                Rectangle()
                    .fill(Color(cgColor: SensitiveContentGuard.strictFill))
                    .aspectRatio(image.size, contentMode: .fit)
                    .overlay { ConcealedBadge(size: size) }
            } else if let image, let concealed {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .blur(radius: concealed ? max(6, size * 0.08) : 0, opaque: true)
                    .clipped()
                    .overlay {
                        if concealed { ConcealedBadge(size: size) }
                    }
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
            }
        }
        .frame(maxWidth: size, maxHeight: size)
        .task(id: "\(pixels)|\(url.path)") {
            if let cached = ThumbnailCache.shared.cached(url, pixels: pixels) {
                image = cached
            } else {
                if let loaded = await ThumbnailCache.shared.thumbnail(for: url, pixels: pixels) { image = loaded }
            }
        }
        // Also when blurring resumes after a pause, so that pictures seen meanwhile get checked.
        .task(id: "\(url.path)|\(guardian.isBlurring)") {
            if guardian.isBlurring { await guardian.check(url, isVideo: isVideo) }
        }
    }
}

/// Marks a video in the grid and the filmstrip.
struct VideoBadge: View {
    var body: some View {
        Image(systemName: "play.fill")
            .font(.caption2)
            .foregroundStyle(.white)
            .padding(4)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
            .padding(4)
            .accessibilityLabel("Video")
    }
}

/// Still images of pictures and videos, made without Quick Look where possible: Quick Look keeps
/// the thumbnails it makes in the system's thumbnail cache on disk, and Motiv should leave
/// nothing behind. Only files that neither ImageIO nor AppKit can read go to Quick Look –
/// unless the user chose the system's cache in the settings for speed.
enum Stills {
    /// At most `pixels` on the larger side, upright.
    nonisolated static func thumbnail(of url: URL, pixels: Int) async -> CGImage? {
        // The user may prefer speed: Quick Look first, as the Finder does.
        if UserDefaults.standard.bool(forKey: Preferences.usesSystemThumbnailCacheKey),
           let image = await quickLook(url, pixels: pixels) {
            return image
        }
        let isVideo = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.conforms(to: .movie) ?? false
        let still = isVideo
            ? await videoFrame(of: url, pixels: pixels)
            : await Task.detached(priority: .userInitiated) { image(of: url, pixels: pixels) }.value
        if let still { return still }
        return await quickLook(url, pixels: pixels)
    }

    /// A frame near the start of a video, as Quick Look would show it.
    nonisolated static func videoFrame(of url: URL, pixels: Int) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: pixels, height: pixels)
        let seconds = (try? await asset.load(.duration))?.seconds ?? 0
        let time = CMTime(seconds: seconds.isFinite ? min(1, seconds / 10) : 0, preferredTimescale: 600)
        return try? await generator.image(at: time).image
    }

    /// Quick Look, for the few formats Motiv cannot read itself.
    nonisolated static func quickLook(_ url: URL, pixels: Int) async -> CGImage? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: pixels, height: pixels),
                                                   scale: 1, representationTypes: .thumbnail)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage
    }

    /// More than 50 megapixels: decoding such a picture needs hundreds of megabytes for a moment.
    nonisolated static func isLarge(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return false }
        return width * height > 50_000_000
    }

    /// ImageIO, and AppKit for what ImageIO does not read, such as SVG. Photos from cameras and
    /// phones usually carry a small preview of their own; if it is large enough, it is used
    /// instead of decoding the whole picture.
    private nonisolated static func image(of url: URL, pixels: Int) -> CGImage? {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            let index = source.largestImageIndex
            var options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
            ]
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
            let largest = max(properties[kCGImagePropertyPixelWidth] as? Int ?? 0, properties[kCGImagePropertyPixelHeight] as? Int ?? 0)
            let wanted = Double(min(pixels, largest > 0 ? largest : pixels)) * 0.9
            if let preview = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary),
               Double(max(preview.width, preview.height)) >= wanted {
                return preview
            }
            options[kCGImageSourceCreateThumbnailFromImageAlways] = true
            if let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) {
                return image
            }
        }
        return drawn(url, pixels: pixels)
    }

    private nonisolated static func drawn(_ url: URL, pixels: Int) -> CGImage? {
        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = Double(pixels) / max(image.size.width, image.size.height)
        let width = max(1, Int((image.size.width * scale).rounded()))
        let height = max(1, Int((image.size.height * scale).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
