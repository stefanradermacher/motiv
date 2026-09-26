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
import ImageIO
import Observation
import UniformTypeIdentifiers

/// A file as loaded for the single-image view.
enum ViewerContent: @unchecked Sendable {
    /// `size` is the picture's full size in pixels, upright. A large picture is decoded smaller
    /// at first, as large as the screen needs; see `ImageViewerModel.sharpenIfNeeded`.
    case still(CGImage, size: CGSize)
    /// An animated GIF; NSImageView plays it.
    case animated(NSImage)
    /// A frame of a video. Motiv does not play videos itself.
    case poster(CGImage)
    case failed
}

/// What the canvas draws: the content, rotated and mirrored as the user chose.
enum CanvasPicture {
    /// Drawn at `size`, the picture's full size, even if the image itself has fewer pixels.
    case image(CGImage, size: CGSize)
    case animated(NSImage)
    /// A small blurred copy of a picture that may be sensitive, shown as large as the picture.
    case concealed(CGImage, size: CGSize)

    var size: CGSize {
        switch self {
        case .image(_, let size): size
        case .animated(let image): image.size
        case .concealed(_, let size): size
        }
    }

    func isSame(as other: CanvasPicture?) -> Bool {
        switch (self, other) {
        case (.image(let a, _), .image(let b, _)?): a === b
        case (.animated(let a), .animated(let b)?): a === b
        case (.concealed(let a, _), .concealed(let b, _)?): a === b
        default: false
        }
    }
}

/// State of the single-image view: the loaded image, its orientation and the zoom.
@MainActor @Observable
final class ImageViewerModel {
    private(set) var item: MediaItem?
    private(set) var content: ViewerContent?
    private(set) var picture: CanvasPicture?
    /// Quarter turns clockwise. Rotating and mirroring only change the view, never the file.
    private(set) var quarterTurns = 0
    private(set) var mirrored = false
    /// Current magnification and fit mode, as reported by the canvas.
    var zoom: CGFloat = 1 {
        didSet { sharpenIfNeeded() }
    }
    var fitMode: FitMode? = .window
    /// Asks the toolbar to show the field for entering a zoom level.
    var requestsZoomInput = false

    /// Zoom levels offered in the zoom menu.
    static let menuZoomLevels: [CGFloat] = [0.25, 0.5, 0.75, 1, 1.5, 2, 4, 8]
    static let zoomRange: ClosedRange<CGFloat> = 0.01...32

    @ObservationIgnored weak var canvas: ImageScrollView?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// The current image and its neighbours, so that stepping through a folder is instant.
    /// Large pictures are kept here only as large as the screen needs.
    @ObservationIgnored private var cache: [URL: ViewerContent] = [:]
    @ObservationIgnored private var preloadTasks: [URL: Task<Void, Never>] = [:]
    /// Loads the current picture at full size, once zooming in needs more pixels.
    @ObservationIgnored private var sharpenTask: Task<Void, Never>?
    @ObservationIgnored private var wanted: Set<URL> = []

    @ObservationIgnored private var concealedSource: CGImage?
    @ObservationIgnored private var concealedCopy: CanvasPicture?
    @ObservationIgnored private var concealedStrict = false

    /// The picture blurred beyond recognition, for pictures that may be sensitive; for a child a
    /// plain area instead. Made once per picture.
    func concealedPicture() -> CanvasPicture? {
        let source: CGImage? = switch content {
        case .still(let image, _), .poster(let image): image
        case .animated(let image): image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        case .failed, nil: nil
        }
        guard let source, let picture else { return nil }
        let strict = SensitiveContentGuard.shared.isStrict
        if source !== concealedSource || strict != concealedStrict {
            concealedSource = source
            concealedStrict = strict
            concealedCopy = SensitiveContentGuard.concealed(source, strict: strict).map { .concealed($0, size: picture.size) }
        }
        return concealedCopy
    }

    var canTransform: Bool {
        if case .still = content { true } else { false }
    }

    var isTransformed: Bool {
        quarterTurns != 0 || mirrored
    }

    func show(_ item: MediaItem, preloading neighbours: [MediaItem]) {
        let isNew = item.url != self.item?.url
        self.item = item
        wanted = Set([item.url] + neighbours.map(\.url))
        cache = cache.filter { wanted.contains($0.key) }
        // Pictures no longer next to the current one need not be decoded any more.
        for (url, task) in preloadTasks where !wanted.contains(url) {
            task.cancel()
            preloadTasks[url] = nil
        }
        let maxPixels = Self.screenPixels

        if isNew {
            quarterTurns = 0
            mirrored = false
            canvas?.prepareForNewPicture()
            loadTask?.cancel()
            sharpenTask?.cancel()
            sharpenTask = nil
            if let cached = cache[item.url] {
                setContent(cached)
            } else {
                content = nil
                picture = nil
                loadTask = Task {
                    let loaded = await Self.load(item, maxPixels: maxPixels)
                    store(loaded, for: item.url)
                    if self.item?.url == item.url { setContent(loaded) }
                }
            }
        }
        // One after the other: several very large pictures decoded at once need gigabytes.
        for neighbour in neighbours where cache[neighbour.url] == nil && preloadTasks[neighbour.url] == nil {
            preloadTasks[neighbour.url] = Task(priority: .utility) {
                await Self.preloadGate.acquire()
                defer { Task { await Self.preloadGate.release() } }
                guard !Task.isCancelled else { return }
                let loaded = await Self.load(neighbour, maxPixels: maxPixels)
                preloadTasks[neighbour.url] = nil
                guard !Task.isCancelled else { return }
                store(loaded, for: neighbour.url)
            }
        }
    }

    /// Loads the current picture at full size when the zoom shows more pixels than the smaller
    /// copy has. The full size is kept only while the picture is shown.
    private func sharpenIfNeeded() {
        guard sharpenTask == nil, needsSharpening, let item else { return }
        sharpenTask = Task {
            // Only a zoom that lasts: while a picture is being fitted, the canvas may briefly
            // report a zoom it does not keep.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, needsSharpening else {
                sharpenTask = nil
                return
            }
            let full = await Self.load(item, maxPixels: nil)
            guard !Task.isCancelled, self.item?.url == item.url, case .still = full else { return }
            setContent(full)
        }
    }

    private var needsSharpening: Bool {
        guard case .still(let image, let size) = content else { return false }
        let pixels = CGFloat(max(image.width, image.height))
        let largest = max(size.width, size.height)
        guard pixels < largest else { return false }
        let scale = canvas?.window?.backingScaleFactor ?? 2
        return zoom * scale * largest > pixels * 1.05
    }

    private func store(_ content: ViewerContent, for url: URL) {
        if wanted.contains(url) { cache[url] = content }
    }

    private func setContent(_ content: ViewerContent) {
        self.content = content
        updatePicture()
    }

    private func updatePicture() {
        switch content {
        case .still(let image, let size):
            let sideways = quarterTurns % 2 == 1
            picture = .image(Self.transformed(image, quarterTurns: quarterTurns, mirrored: mirrored),
                             size: sideways ? CGSize(width: size.height, height: size.width) : size)
        case .poster(let image):
            picture = .image(image, size: CGSize(width: image.width, height: image.height))
        case .animated(let image):
            picture = .animated(image)
        case .failed, nil:
            picture = nil
        }
    }

    // MARK: Orientation

    func rotateRight() {
        quarterTurns = (quarterTurns + 1) % 4
        updatePicture()
    }

    func rotateLeft() {
        quarterTurns = (quarterTurns + 3) % 4
        updatePicture()
    }

    // The picture is shown as rotation after mirroring. Mirroring what is on screen reverses
    // the direction of the rotation; mirroring vertically is mirroring horizontally plus half a turn.

    func flipHorizontally() {
        mirrored.toggle()
        quarterTurns = (4 - quarterTurns) % 4
        updatePicture()
    }

    func flipVertically() {
        mirrored.toggle()
        quarterTurns = (6 - quarterTurns) % 4
        updatePicture()
    }

    func resetOrientation() {
        quarterTurns = 0
        mirrored = false
        updatePicture()
    }

    // MARK: Zoom

    func zoomIn() { canvas?.zoom(by: 1.25) }
    func zoomOut() { canvas?.zoom(by: 1 / 1.25) }
    func actualSize() { canvas?.setZoom(1) }
    func setZoom(_ value: CGFloat) { canvas?.setZoom(min(max(value, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)) }
    func fit(_ mode: FitMode) { canvas?.fit(mode) }

    // MARK: Loading

    /// The largest side, in pixels, of the largest screen: more a picture cannot show when fitted.
    private static var screenPixels: Int {
        let sides = NSScreen.screens.map { max($0.frame.width, $0.frame.height) * $0.backingScaleFactor }
        return Int(sides.max() ?? 5120)
    }

    private static let preloadGate = Limiter(limit: 1)

    /// `maxPixels` limits the larger side; nil decodes the full size.
    private nonisolated static func load(_ item: MediaItem, maxPixels: Int?) async -> ViewerContent {
        if item.isVideo {
            if let frame = await Stills.videoFrame(of: item.url, pixels: 2048) { return .poster(frame) }
            return await Stills.quickLook(item.url, pixels: 2048).map { .poster($0) } ?? .failed
        }
        let url = item.url
        return await Task.detached(priority: .userInitiated) { decode(url, maxPixels: maxPixels) }.value
    }

    private nonisolated static func decode(_ url: URL, maxPixels: Int?) -> ViewerContent {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return decodeWithAppKit(url) }
        if CGImageSourceGetCount(source) > 1,
           CGImageSourceGetType(source) as String? == UTType.gif.identifier,
           let image = NSImage(contentsOf: url) {
            return .animated(image)
        }
        let index = source.largestImageIndex
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let largest = max(width, height, 1)
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        // At full size and upright, the image itself: a thumbnail of the full size would hold
        // the pixels twice while it is made.
        if orientation == 1, maxPixels.map({ largest <= $0 }) ?? true,
           let image = CGImageSourceCreateImageAtIndex(source, index, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
            return .still(image, size: CGSize(width: image.width, height: image.height))
        }
        // Decoding as a thumbnail applies the orientation stored in the file, and for a large
        // picture it decodes only as many pixels as the screen can show.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(largest, maxPixels ?? largest),
        ]
        if let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) {
            // The full size upright: orientations 5 to 8 turn the picture sideways.
            let turned = orientation >= 5
            let size = turned ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
            return .still(image, size: size == .zero ? CGSize(width: image.width, height: image.height) : size)
        }
        return decodeWithAppKit(url)
    }

    /// For formats ImageIO does not read, such as SVG.
    private nonisolated static func decodeWithAppKit(_ url: URL) -> ViewerContent {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return .failed }
        return .still(cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
    }

    private nonisolated static func transformed(_ image: CGImage, quarterTurns: Int, mirrored: Bool) -> CGImage {
        guard quarterTurns != 0 || mirrored else { return image }
        let width = image.width
        let height = image.height
        let sideways = quarterTurns % 2 == 1
        let colorSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.displayP3)!
        guard let context = CGContext(data: nil, width: sideways ? height : width, height: sideways ? width : height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.translateBy(x: CGFloat(context.width) / 2, y: CGFloat(context.height) / 2)
        context.rotate(by: -CGFloat(quarterTurns) * .pi / 2)
        if mirrored { context.scaleBy(x: -1, y: 1) }
        context.draw(image, in: CGRect(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2,
                                       width: CGFloat(width), height: CGFloat(height)))
        return context.makeImage() ?? image
    }
}

