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

/// Printing, as in Preview: one image per page, as large as the printable area allows and turned
/// a quarter if the image is wider than the page is high or the other way round.
@MainActor
enum ImagePrinter {
    /// Pixels for the larger side: enough for 300 dpi on A3, without decoding huge images in full.
    static let maxPixels = 6000

    /// Asks for paper size and orientation; Motiv keeps them for later print jobs until it quits.
    static func pageSetup(for window: NSWindow?) {
        let layout = NSPageLayout()
        if let window {
            layout.beginSheet(using: NSPrintInfo.shared, on: window)
        } else {
            layout.runModal(with: NSPrintInfo.shared)
        }
    }

    /// Prints `urls`. Images hidden as possibly sensitive are left out; if nothing is left, Motiv
    /// only beeps. `quarterTurns` and `mirrored` are the view's orientation, for the image shown.
    static func print(_ urls: [URL], title: String, quarterTurns: Int = 0, mirrored: Bool = false, in window: NSWindow?) async {
        let sensitive = SensitiveContentGuard.shared
        var printable: [URL] = []
        for url in urls {
            await sensitive.check(url, isVideo: false)
            if sensitive.isConcealed(url) != true { printable.append(url) }
        }
        guard !printable.isEmpty else {
            NSSound.beep()
            return
        }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        // Like Preview: landscape for wide images, so the preview shows them the right way up.
        let shapes = printable.compactMap { uprightSize(of: $0, quarterTurns: quarterTurns) }
        if !shapes.isEmpty {
            let wide = shapes.filter { $0.width > $0.height }.count
            info.orientation = wide * 2 > shapes.count ? .landscape : .portrait
        }
        let view = ImagePrintView(urls: printable, quarterTurns: quarterTurns, mirrored: mirrored)
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = title
        operation.printPanel.options.formUnion([.showsPaperSize, .showsOrientation, .showsPreview])
        if let window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }

    /// The image's size as shown, read from the file without decoding it.
    private static func uprightSize(of url: URL, quarterTurns: Int) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, source.largestImageIndex, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        // Orientations 5 to 8 stored in the file turn the image sideways, as does an odd number of quarter turns.
        let fileTurned = (properties[kCGImagePropertyOrientation] as? Int ?? 1) >= 5
        let sideways = fileTurned != (quarterTurns % 2 == 1)
        return sideways ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }
}

/// All pages one below the other; the print system asks for them one at a time.
private final class ImagePrintView: NSView {
    private let urls: [URL]
    private let quarterTurns: Int
    private let mirrored: Bool
    /// The page drawn last: the print panel's preview draws a page more than once.
    private var cached: (index: Int, image: CGImage)?

    init(urls: [URL], quarterTurns: Int, mirrored: Bool) {
        self.urls = urls
        self.quarterTurns = quarterTurns
        self.mirrored = mirrored
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    /// The printable area of the paper chosen now; it changes when the user picks other paper
    /// or orientation in the print panel.
    private var pageSize: NSSize {
        (NSPrintOperation.current?.printInfo ?? NSPrintInfo.shared).imageablePageBounds.size
    }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        if let info = NSPrintOperation.current?.printInfo {
            // Use all of the paper the printer can reach, as Preview does.
            let bounds = info.imageablePageBounds
            let paper = info.paperSize
            info.leftMargin = bounds.minX
            info.rightMargin = paper.width - bounds.maxX
            info.bottomMargin = bounds.minY
            info.topMargin = paper.height - bounds.maxY
        }
        let size = pageSize
        setFrameSize(NSSize(width: size.width, height: size.height * CGFloat(urls.count)))
        range.pointee = NSRange(location: 1, length: urls.count)
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        let size = pageSize
        return NSRect(x: 0, y: CGFloat(page - 1) * size.height, width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let size = pageSize
        guard size.height > 0 else { return }
        let index = Int(dirtyRect.midY / size.height)
        guard urls.indices.contains(index),
              let image = image(at: index),
              let context = NSGraphicsContext.current?.cgContext
        else { return }

        let page = rectForPage(index + 1)
        let imageSize = CGSize(width: image.width, height: image.height)
        let turn = imageSize.width != imageSize.height
            && (imageSize.width > imageSize.height) != (page.width > page.height)
        let upright = turn ? CGSize(width: imageSize.height, height: imageSize.width) : imageSize
        let scale = min(page.width / upright.width, page.height / upright.height)
        let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

        context.saveGState()
        context.interpolationQuality = .high
        context.translateBy(x: page.midX, y: page.midY)
        // The view is flipped; images are drawn the right way up in an unflipped space.
        context.scaleBy(x: 1, y: -1)
        if turn { context.rotate(by: .pi / 2) }
        context.draw(image, in: CGRect(x: -drawn.width / 2, y: -drawn.height / 2, width: drawn.width, height: drawn.height))
        context.restoreGState()
    }

    private func image(at index: Int) -> CGImage? {
        if let cached, cached.index == index { return cached.image }
        let decoded: CGImage? = switch ImageViewerModel.decode(urls[index], maxPixels: ImagePrinter.maxPixels) {
        case .still(let image, _), .poster(let image): image
        case .animated(let image): image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        case .failed: nil
        }
        guard let decoded else { return nil }
        let image = ImageViewerModel.transformed(decoded, quarterTurns: quarterTurns, mirrored: mirrored)
        cached = (index, image)
        return image
    }
}

extension Gallery {
    /// The images the print command acts on: the image shown or the selected ones, without videos.
    var printableURLs: [URL] {
        targetURLs.filter { !(item(for: $0)?.isVideo ?? false) }
    }

    /// Whether at least one of them is not hidden as possibly sensitive.
    var canPrint: Bool {
        printableURLs.contains { SensitiveContentGuard.shared.isConcealed($0) != true }
    }

    func printImages() {
        let urls = printableURLs
        guard !urls.isEmpty else { return }
        let title = urls.count == 1
            ? urls[0].deletingPathExtension().lastPathComponent
            : (folder?.lastPathComponent ?? "Motiv")
        let viewing = mode == .view
        let quarterTurns = viewing ? viewer.quarterTurns : 0
        let mirrored = viewing ? viewer.mirrored : false
        let window = NSApp.keyWindow
        Task {
            await ImagePrinter.print(urls, title: title, quarterTurns: quarterTurns, mirrored: mirrored, in: window)
        }
    }
}
