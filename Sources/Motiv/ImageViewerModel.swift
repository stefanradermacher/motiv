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
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// A file as loaded for the single-image view.
enum ViewerContent: @unchecked Sendable {
    case still(CGImage)
    /// An animated GIF; NSImageView plays it.
    case animated(NSImage)
    /// A frame of a video. Motiv does not play videos itself.
    case poster(CGImage)
    case failed
}

/// What the canvas draws: the content, rotated and mirrored as the user chose.
enum CanvasPicture {
    case image(CGImage)
    case animated(NSImage)
    /// A small blurred copy of a picture that may be sensitive, shown as large as the picture.
    case concealed(CGImage, size: CGSize)

    var size: CGSize {
        switch self {
        case .image(let image): CGSize(width: image.width, height: image.height)
        case .animated(let image): image.size
        case .concealed(_, let size): size
        }
    }

    func isSame(as other: CanvasPicture?) -> Bool {
        switch (self, other) {
        case (.image(let a), .image(let b)?): a === b
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
    var zoom: CGFloat = 1
    var fitMode: FitMode? = .window
    /// Asks the toolbar to show the field for entering a zoom level.
    var requestsZoomInput = false

    /// Zoom levels offered in the zoom menu.
    static let menuZoomLevels: [CGFloat] = [0.25, 0.5, 0.75, 1, 1.5, 2, 4, 8]
    static let zoomRange: ClosedRange<CGFloat> = 0.01...32

    @ObservationIgnored weak var canvas: ImageScrollView?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// The current image and its neighbours, so that stepping through a folder is instant.
    @ObservationIgnored private var cache: [URL: ViewerContent] = [:]
    @ObservationIgnored private var wanted: Set<URL> = []

    @ObservationIgnored private var concealedSource: CGImage?
    @ObservationIgnored private var concealedCopy: CanvasPicture?

    /// The picture blurred beyond recognition, for pictures that may be sensitive. Made once per picture.
    func concealedPicture() -> CanvasPicture? {
        let source: CGImage? = switch content {
        case .still(let image), .poster(let image): image
        case .animated(let image): image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        case .failed, nil: nil
        }
        guard let source, let picture else { return nil }
        if source !== concealedSource {
            concealedSource = source
            concealedCopy = SensitiveContentGuard.blurred(source).map { .concealed($0, size: picture.size) }
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

        if isNew {
            quarterTurns = 0
            mirrored = false
            canvas?.prepareForNewPicture()
            loadTask?.cancel()
            if let cached = cache[item.url] {
                setContent(cached)
            } else {
                content = nil
                picture = nil
                loadTask = Task {
                    let loaded = await Self.load(item)
                    store(loaded, for: item.url)
                    if self.item?.url == item.url { setContent(loaded) }
                }
            }
        }
        for neighbour in neighbours where cache[neighbour.url] == nil {
            Task(priority: .utility) {
                store(await Self.load(neighbour), for: neighbour.url)
            }
        }
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
        case .still(let image):
            picture = .image(Self.transformed(image, quarterTurns: quarterTurns, mirrored: mirrored))
        case .poster(let image):
            picture = .image(image)
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

    private nonisolated static func load(_ item: MediaItem) async -> ViewerContent {
        if item.isVideo {
            let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 2048, height: 2048),
                                                       scale: 1, representationTypes: .thumbnail)
            guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            else { return .failed }
            return .poster(representation.cgImage)
        }
        let url = item.url
        return await Task.detached(priority: .userInitiated) { decode(url) }.value
    }

    private nonisolated static func decode(_ url: URL) -> ViewerContent {
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
        // Decoding as a full-size thumbnail applies the orientation stored in the file.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height, 1),
        ]
        if let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) {
            return .still(image)
        }
        return decodeWithAppKit(url)
    }

    /// For formats ImageIO does not read, such as SVG.
    private nonisolated static func decodeWithAppKit(_ url: URL) -> ViewerContent {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return .failed }
        return .still(cgImage)
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
