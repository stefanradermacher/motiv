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

/// Printing, as in Preview: one image per page, scaled and turned to suit the paper as chosen in
/// Motiv's section of the print panel (`PrintOptions`).
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
        operation.printPanel.addAccessoryController(PrintOptions())
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
    private var cached: (index: Int, picture: Picture)?

    /// An image to print and its size on paper at its own resolution, in points.
    private struct Picture {
        let image: CGImage
        let actualSize: CGSize
    }

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
              let picture = picture(at: index),
              let context = NSGraphicsContext.current?.cgContext
        else { return }

        let page = rectForPage(index + 1)
        let imageSize = picture.actualSize
        let turn = PrintOptions.rotates
            && imageSize.width != imageSize.height
            && (imageSize.width > imageSize.height) != (page.width > page.height)
        let upright = turn ? CGSize(width: imageSize.height, height: imageSize.width) : imageSize
        let fitting = min(page.width / upright.width, page.height / upright.height)
        let scale: CGFloat = switch PrintOptions.scaling {
        case .actualSize: 1
        case .shrinkToFit: min(fitting, 1)
        case .scaleToFit: fitting
        }
        let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

        context.saveGState()
        // At actual size a large image is cut off at the edge of the page, as in Preview.
        context.clip(to: page)
        context.interpolationQuality = .high
        context.translateBy(x: page.midX, y: page.midY)
        // The view is flipped; images are drawn the right way up in an unflipped space.
        context.scaleBy(x: 1, y: -1)
        if turn { context.rotate(by: .pi / 2) }
        context.draw(picture.image, in: CGRect(x: -drawn.width / 2, y: -drawn.height / 2, width: drawn.width, height: drawn.height))
        context.restoreGState()
    }

    private func picture(at index: Int) -> Picture? {
        if let cached, cached.index == index { return cached.picture }
        let url = urls[index]
        let decoded: (CGImage, CGSize)? = switch ImageViewerModel.decode(url, maxPixels: ImagePrinter.maxPixels) {
        case .still(let image, let size): (image, size)
        case .poster(let image): (image, CGSize(width: image.width, height: image.height))
        case .animated(let image): image.cgImage(forProposedRect: nil, context: nil, hints: nil).map { ($0, image.size) }
        case .failed: nil
        }
        guard let (decoded, pixels) = decoded else { return nil }
        let image = ImageViewerModel.transformed(decoded, quarterTurns: quarterTurns, mirrored: mirrored)
        // The full size, not the decoded one, at the resolution stored in the file; 72 dpi if none is.
        let dpi = Self.resolution(of: url)
        let sideways = quarterTurns % 2 == 1
        let size = CGSize(width: (sideways ? pixels.height : pixels.width) * 72 / dpi.width,
                          height: (sideways ? pixels.width : pixels.height) * 72 / dpi.height)
        let picture = Picture(image: image, actualSize: size)
        cached = (index, picture)
        return picture
    }

    private static func resolution(of url: URL) -> CGSize {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, source.largestImageIndex, nil) as? [CFString: Any]
        else { return CGSize(width: 72, height: 72) }
        let x = (properties[kCGImagePropertyDPIWidth] as? Double).flatMap { $0 > 0 ? $0 : nil } ?? 72
        let y = (properties[kCGImagePropertyDPIHeight] as? Double).flatMap { $0 > 0 ? $0 : nil } ?? x
        // Orientations 5 to 8 swap the axes.
        let turned = (properties[kCGImagePropertyOrientation] as? Int ?? 1) >= 5
        return turned ? CGSize(width: y, height: x) : CGSize(width: x, height: y)
    }
}

/// Motiv's section of the print panel, as in Leser: whether images are turned to match the paper,
/// and how they are scaled. The choice is remembered for the next print; the preview follows it.
final class PrintOptions: NSViewController, NSPrintPanelAccessorizing {
    enum Scaling: Int {
        case actualSize, shrinkToFit, scaleToFit
    }

    private static let scalingKey = "printScaling"
    private static let rotatesKey = "printAutoRotate"

    /// Unlike Leser, scaled to the paper by default, as Preview prints images.
    static var scaling: Scaling {
        Scaling(rawValue: UserDefaults.standard.object(forKey: scalingKey) as? Int ?? -1) ?? .scaleToFit
    }

    static var rotates: Bool {
        UserDefaults.standard.object(forKey: rotatesKey) as? Bool ?? true
    }

    /// Observed by the print panel, which then draws its preview again.
    @objc dynamic var scalingMode = PrintOptions.scaling.rawValue {
        didSet {
            UserDefaults.standard.set(scalingMode, forKey: Self.scalingKey)
            updateButtons()
        }
    }

    @objc dynamic var autoRotates = PrintOptions.rotates {
        didSet {
            UserDefaults.standard.set(autoRotates, forKey: Self.rotatesKey)
            updateButtons()
        }
    }

    private let rotateButton = NSButton(checkboxWithTitle: String(localized: "Bilder automatisch drehen"),
                                        target: nil, action: nil)
    private let scalingButtons: [(Scaling, NSButton)] = [
        (.actualSize, NSButton(radioButtonWithTitle: String(localized: "Originalgröße"), target: nil, action: nil)),
        (.shrinkToFit, NSButton(radioButtonWithTitle: String(localized: "Große Bilder verkleinern"), target: nil, action: nil)),
        (.scaleToFit, NSButton(radioButtonWithTitle: String(localized: "Auf Papierformat skalieren"), target: nil, action: nil)),
    ]

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Motiv"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        rotateButton.target = self
        rotateButton.action = #selector(rotateChanged)
        for (_, button) in scalingButtons {
            button.target = self
            button.action = #selector(scalingChanged)
        }
        let scalingLabel = NSTextField(labelWithString: String(localized: "Bildskalierung:"))
        let scalingStack = NSStackView(views: scalingButtons.map(\.1))
        scalingStack.orientation = .vertical
        scalingStack.alignment = .leading
        scalingStack.spacing = 6

        let stack = NSStackView(views: [rotateButton, scalingLabel, scalingStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(14, after: rotateButton)
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        view = stack
        updateButtons()
    }

    private func updateButtons() {
        guard isViewLoaded else { return }
        rotateButton.state = autoRotates ? .on : .off
        for (mode, button) in scalingButtons {
            button.state = mode.rawValue == scalingMode ? .on : .off
        }
    }

    @objc private func rotateChanged() {
        autoRotates = rotateButton.state == .on
    }

    @objc private func scalingChanged(_ sender: NSButton) {
        guard let mode = scalingButtons.first(where: { $0.1 === sender })?.0 else { return }
        scalingMode = mode.rawValue
    }

    // MARK: NSPrintPanelAccessorizing

    func localizedSummaryItems() -> [[NSPrintPanel.AccessorySummaryKey: String]] {
        let scaling = scalingButtons.first { $0.0.rawValue == scalingMode }?.1.title ?? ""
        return [
            [.itemName: String(localized: "Bildskalierung"), .itemDescription: scaling],
            [.itemName: String(localized: "Bilder automatisch drehen"),
             .itemDescription: autoRotates ? String(localized: "Ein") : String(localized: "Aus")],
        ]
    }

    func keyPathsForValuesAffectingPreview() -> Set<String> {
        ["scalingMode", "autoRotates"]
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
