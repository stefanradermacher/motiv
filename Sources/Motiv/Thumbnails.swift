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
import QuickLookThumbnailing
import SwiftUI

/// Thumbnails of images and videos, made by Quick Look and kept in memory.
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

    func thumbnail(for url: URL, pixels: Int) async -> NSImage {
        if let image = cached(url, pixels: pixels) { return image }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: pixels, height: pixels),
                                                   scale: 1, representationTypes: .thumbnail)
        let image: NSImage
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            image = representation.nsImage
        } else {
            image = NSWorkspace.shared.icon(forFile: url.path)
        }
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
            if let image, let concealed {
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
                image = await ThumbnailCache.shared.thumbnail(for: url, pixels: pixels)
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
