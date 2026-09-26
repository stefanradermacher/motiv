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
import SwiftUI

/// The picture of the single-image view, in an AppKit scroll view: that gives trackpad zoom,
/// smooth scrolling and a picture that stays centred when it is smaller than the window.
struct ImageCanvas: NSViewRepresentable {
    let picture: CanvasPicture?
    let enlargesSmallImages: Bool
    /// Only the image, full screen: on black, without a pointer.
    let isPresenting: Bool
    let model: ImageViewerModel

    func makeNSView(context: Context) -> ImageScrollView {
        let view = ImageScrollView()
        view.onZoomChange = { [weak model] zoom, fitMode in
            model?.zoom = zoom
            model?.fitMode = fitMode
        }
        model.canvas = view
        return view
    }

    func updateNSView(_ view: ImageScrollView, context: Context) {
        model.canvas = view
        view.enlargesSmallImages = enlargesSmallImages
        view.backgroundColor = isPresenting ? .black : .underPageBackgroundColor
        view.show(picture)
        if isPresenting { NSCursor.setHiddenUntilMouseMoves(true) }
    }
}

/// How the picture follows the window size.
enum FitMode: CaseIterable {
    /// The whole picture is visible.
    case window
    /// As wide as the window; taller pictures scroll.
    case width
    /// As high as the window; wider pictures scroll.
    case height

    var title: String {
        switch self {
        case .window: String(localized: "An Fenster anpassen")
        case .width: String(localized: "An Breite anpassen")
        case .height: String(localized: "An Höhe anpassen")
        }
    }
}

final class ImageScrollView: NSScrollView {
    /// Reports the magnification and the fit mode, nil after zooming by hand.
    var onZoomChange: ((CGFloat, FitMode?) -> Void)?
    /// How the picture follows the window size. Zooming by hand sets it to nil.
    private(set) var fitMode: FitMode? = .window
    /// The setting for pictures smaller than the window, when they are fitted automatically.
    var enlargesSmallImages = false {
        didSet { if fitMode != nil && enlargesSmallImages != oldValue { applyFit() } }
    }
    /// Set when a fit was chosen explicitly: then small pictures are enlarged too, whatever the
    /// setting. Fitting to the whole window when a picture opens follows the setting.
    private var fitsOnRequest = false

    private let pictureView = PictureView()
    private var picture: CanvasPicture?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        contentView = CenteringClipView()
        documentView = pictureView
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        allowsMagnification = true
        minMagnification = 0.01
        maxMagnification = 32
        backgroundColor = .underPageBackgroundColor
        pictureView.onDoubleClick = { [weak self] point in self?.toggleZoom(at: point) }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(willStartMagnifying), name: NSScrollView.willStartLiveMagnifyNotification, object: self)
        center.addObserver(self, selector: #selector(didEndMagnifying), name: NSScrollView.didEndLiveMagnifyNotification, object: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func willStartMagnifying(_ notification: Notification) {
        fitMode = nil
    }

    @objc private func didEndMagnifying(_ notification: Notification) {
        reportZoom()
    }

    /// The next picture keeps a fit to width or height; after zooming by hand, it is fitted to
    /// the window again.
    func prepareForNewPicture() {
        if fitMode == nil || fitMode == .window {
            fitMode = .window
            fitsOnRequest = false
        }
    }

    func show(_ picture: CanvasPicture?) {
        guard !(picture?.isSame(as: self.picture) ?? (self.picture == nil)) else { return }
        self.picture = picture
        pictureView.picture = picture
        pictureView.frame = NSRect(origin: .zero, size: picture?.size ?? .zero)
        if fitMode != nil {
            applyFit()
        } else {
            centerPicture()
        }
    }

    /// Fits the picture as chosen by the user; this also enlarges pictures smaller than the window.
    func fit(_ mode: FitMode) {
        fitMode = mode
        fitsOnRequest = true
        applyFit()
        scrollToStart()
    }

    private func applyFit() {
        guard let fitMode, let size = picture?.size, size.width > 0, size.height > 0 else { return }
        let available = contentSize
        let widthScale = available.width / size.width
        let heightScale = available.height / size.height
        var scale = switch fitMode {
        case .window: min(widthScale, heightScale)
        case .width: widthScale
        case .height: heightScale
        }
        if !enlargesSmallImages && !fitsOnRequest { scale = min(scale, 1) }
        minMagnification = min(0.01, scale)
        magnification = scale
        reportZoom()
    }

    /// After fitting to width or height, the start of the picture is visible: its top or left edge.
    private func scrollToStart() {
        let size = pictureView.frame.size
        let visible = contentView.bounds.size
        let origin = NSPoint(x: fitMode == .height ? 0 : (size.width - visible.width) / 2,
                             y: fitMode == .width ? size.height - visible.height : (size.height - visible.height) / 2)
        contentView.scroll(to: contentView.constrainBoundsRect(NSRect(origin: origin, size: visible)).origin)
        reflectScrolledClipView(contentView)
    }

    func setZoom(_ value: CGFloat, centeredAt point: NSPoint? = nil) {
        guard picture != nil else { return }
        fitMode = nil
        fitsOnRequest = false
        let visible = documentVisibleRect
        let center = point ?? NSPoint(x: visible.midX, y: visible.midY)
        setMagnification(min(max(value, minMagnification), maxMagnification), centeredAt: center)
        reportZoom()
    }

    func zoom(by factor: CGFloat) {
        setZoom(magnification * factor)
    }

    /// Double-click: from the fitted picture to 100 % at the point clicked, and back.
    private func toggleZoom(at point: NSPoint) {
        if fitMode != nil && abs(magnification - 1) > 0.001 {
            setZoom(1, centeredAt: point)
        } else {
            fitMode = .window
            fitsOnRequest = false
            applyFit()
        }
    }

    private func centerPicture() {
        let size = pictureView.frame.size
        let visible = contentView.bounds.size
        contentView.scroll(to: NSPoint(x: (size.width - visible.width) / 2, y: (size.height - visible.height) / 2))
        reflectScrolledClipView(contentView)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if fitMode != nil { applyFit() }
    }

    /// Reported later, because this may run while SwiftUI updates its views.
    private func reportZoom() {
        let value = magnification
        let mode = fitMode
        DispatchQueue.main.async { [weak self] in self?.onZoomChange?(value, mode) }
    }
}

/// Keeps the picture centred when it is smaller than the visible area.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let size = documentView.frame.size
        if rect.width > size.width { rect.origin.x = (size.width - rect.width) / 2 }
        if rect.height > size.height { rect.origin.y = (size.height - rect.height) / 2 }
        return rect
    }
}

/// Draws the picture as the contents of its own layer, which the scroll view scales without
/// redrawing. Dragging moves the picture, a double-click zooms.
final class PictureView: NSView {
    var onDoubleClick: ((NSPoint) -> Void)?
    var picture: CanvasPicture? {
        didSet { update() }
    }

    private let animationView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay

        animationView.imageScaling = .scaleAxesIndependently
        animationView.animates = true
        animationView.autoresizingMask = [.width, .height]
        animationView.isHidden = true
        addSubview(animationView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.contentsGravity = .resize
        // Smooth when a large photo is scaled far down.
        layer.minificationFilter = .trilinear
        switch picture {
        case .image(let image), .concealed(let image, _): layer.contents = image
        case .animated, nil: layer.contents = nil
        }
    }

    private func update() {
        if case .animated(let image) = picture {
            animationView.image = image
            animationView.isHidden = false
        } else {
            animationView.image = nil
            animationView.isHidden = true
        }
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?(convert(event.locationInWindow, from: nil))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let scrollView = enclosingScrollView else { return }
        let clipView = scrollView.contentView
        let scale = scrollView.magnification
        var origin = clipView.bounds.origin
        origin.x -= event.deltaX / scale
        origin.y += event.deltaY / scale
        let bounds = clipView.constrainBoundsRect(NSRect(origin: origin, size: clipView.bounds.size))
        clipView.scroll(to: bounds.origin)
        scrollView.reflectScrolledClipView(clipView)
    }
}
