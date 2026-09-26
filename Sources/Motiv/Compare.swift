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
import Observation
import SwiftUI

/// Two to four pictures compared: side by side, or on top of each other – switching between them,
/// blending one into the other, or with a divider across.
@MainActor @Observable
final class CompareModel {
    enum Layout: String, CaseIterable {
        /// Next to each other; four as 2 × 2.
        case sideBySide
        /// At the same place, one at a time (A/B).
        case overlay
        /// Two pictures on top of each other, the upper one faded in and out with a slider.
        case blend
        /// Two pictures on top of each other, the first left of a divider, the second right of it.
        case split

        /// All layouts but side by side show the pictures at the same place.
        var isStacked: Bool { self != .sideBySide }
        /// Blending and the divider show a pair of pictures.
        var showsPair: Bool { self == .blend || self == .split }
    }

    /// How linked pictures correspond.
    enum Matching {
        /// The same part of each picture, whatever its resolution.
        case sameArea
        /// The same magnification: a picture with twice the pixels appears twice as large.
        case samePixels
    }

    static let itemRange = 2...4

    let items: [MediaItem]
    let viewers: [ImageViewerModel]
    var layout = Layout.sideBySide
    /// Zooming and moving one picture does the same to the others.
    var isLinked = true
    var matching = Matching.sameArea
    /// The picture shown on top when switching between them, and the first of the pair.
    var active = 0
    /// The second picture of the pair for blending and the divider.
    var partner = 1
    /// How far the second picture is faded in, 0 to 1.
    var blend = 0.5
    /// Where the divider stands, as a share of the width from the left.
    var split = 0.5

    @ObservationIgnored private var canvases: [Int: WeakCanvas] = [:]
    @ObservationIgnored private var isSyncing = false
    /// The part all pictures show while in step; nil while they are fitted to the window.
    /// Switching the layout builds new views, which take it over.
    @ObservationIgnored private var sharedView: SharedView?

    private struct WeakCanvas {
        weak var view: ImageScrollView?
    }

    private enum SharedView {
        case area(center: CGPoint, widthShare: CGFloat)
        case pixels(center: CGPoint, magnification: CGFloat)
        /// On top of each other and fitted: every picture fills the window, small ones enlarged,
        /// so that pictures of the same shape lie exactly on top of each other.
        case fittedToWindow
    }

    init(items: [MediaItem]) {
        self.items = items
        viewers = items.map { item in
            let viewer = ImageViewerModel()
            viewer.show(item, preloading: [])
            return viewer
        }
    }

    /// Letters to tell the pictures apart: A, B, C, D.
    static func letter(_ index: Int) -> String {
        String(UnicodeScalar(UInt8(65 + index)))
    }

    /// The pair for blending and the divider: first is below, or left of the divider.
    var first: Int { active }
    var second: Int { partner != active && items.indices.contains(partner) ? partner : (active + 1) % items.count }

    /// Pictures at the same place are always in step, so that only the picture changes.
    private var keepsInStep: Bool {
        isLinked || layout.isStacked
    }

    func register(_ canvas: ImageScrollView, at index: Int) {
        canvases[index] = WeakCanvas(view: canvas)
        canvas.countsRequestedFitAsFitted = layout.isStacked
        canvas.onViewportChange = { [weak self] view in self?.viewportChanged(in: view) }
        guard keepsInStep, let sharedView else { return }
        // After SwiftUI has handed the new view its picture.
        DispatchQueue.main.async { [weak canvas] in
            canvas.map { Self.apply(sharedView, to: $0) }
        }
    }

    func show(_ index: Int) {
        guard items.indices.contains(index) else { return }
        if index == partner { partner = active }
        active = index
    }

    func showNext(_ offset: Int = 1) {
        show((active + offset + items.count) % items.count)
    }

    /// Exchanges the two pictures of the pair.
    func swapPair() {
        let (a, b) = (first, second)
        active = b
        partner = a
    }

    func setSecond(_ index: Int) {
        guard items.indices.contains(index) else { return }
        if index == active { active = second }
        partner = index
    }

    // MARK: Zoom, applied to all pictures

    private var views: [ImageScrollView] {
        canvases.keys.sorted().compactMap { canvases[$0]?.view }
    }

    /// With linked pictures, one leads and the others follow; otherwise each is zoomed on its own.
    private var leadingViews: [ImageScrollView] {
        guard keepsInStep else { return views }
        return canvases[active]?.view.map { [$0] } ?? Array(views.prefix(1))
    }

    func zoom(by factor: CGFloat) { leadingViews.forEach { $0.zoom(by: factor) } }
    func actualSize() { leadingViews.forEach { $0.setZoom(1) } }

    /// Each picture fitted on its own – or, pixel for pixel, all at the size that fits the largest.
    func fitAll() {
        if matching == .sameArea && layout.isStacked {
            sharedView = .fittedToWindow
            isSyncing = true
            views.forEach { $0.fit(.window) }
            isSyncing = false
            return
        }
        guard matching == .samePixels, keepsInStep else {
            views.forEach { $0.fitAutomatically() }
            return
        }
        guard let scale = views.compactMap(\.fittingMagnification).min() else { return }
        isSyncing = true
        views.forEach { $0.follow(center: CGPoint(x: 0.5, y: 0.5), magnification: scale) }
        isSyncing = false
        sharedView = .pixels(center: CGPoint(x: 0.5, y: 0.5), magnification: scale)
    }

    // MARK: Keeping in step

    /// When one picture is zoomed or moved, the others follow: showing the same part of theirs,
    /// or pixel for pixel at the same magnification. A fitted picture makes the others fit too.
    private func viewportChanged(in source: ImageScrollView) {
        guard keepsInStep, !isSyncing, let viewport = source.viewport else { return }
        isSyncing = true
        defer { isSyncing = false }
        let others = views.filter { $0 !== source }
        switch matching {
        // Side by side, each picture fits its own panel.
        case .sameArea where source.fitMode == .window && !layout.isStacked:
            sharedView = nil
            others.filter { $0.fitMode != .window }.forEach { $0.fitAutomatically() }
        // On top of each other they have to match: all fill the window, small ones enlarged.
        case .sameArea where source.fitMode == .window:
            sharedView = .fittedToWindow
            views.filter { !$0.isFittedOnRequest }.forEach { $0.fit(.window) }
            return
        case .sameArea:
            sharedView = .area(center: viewport.center, widthShare: viewport.widthShare)
        case .samePixels:
            sharedView = .pixels(center: viewport.center, magnification: source.magnification)
        }
        if let sharedView { others.forEach { Self.apply(sharedView, to: $0) } }
    }

    private static func apply(_ view: SharedView, to canvas: ImageScrollView) {
        switch view {
        case .area(let center, let widthShare): canvas.follow(center: center, widthShare: widthShare)
        case .pixels(let center, let magnification): canvas.follow(center: center, magnification: magnification)
        case .fittedToWindow: canvas.fit(.window)
        }
    }

    /// After switching the layout, linking or matching, bring the others in line with the first.
    func alignToActive() {
        if matching == .samePixels && keepsInStep && sharedView == nil {
            fitAll()
            return
        }
        guard let source = canvases[active]?.view else { return }
        viewportChanged(in: source)
    }
}

/// The comparison: the pictures with their names, dimensions and sizes.
struct CompareView: View {
    @Bindable var gallery: Gallery
    @Bindable var compare: CompareModel
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            switch compare.layout {
            case .sideBySide:
                sideBySide
            case .overlay, .blend, .split:
                stacked
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: [.down, .repeat]) { press in handle(press) }
        .onExitCommand { gallery.closeCompare() }
        .onAppear { focused = true }
        .onChange(of: compare.layout) {
            compare.alignToActive()
            // The new layout builds new picture views; the keys must stay with the comparison.
            refocus()
        }
        .onChange(of: compare.isLinked) { compare.alignToActive() }
        .onChange(of: compare.matching) { compare.alignToActive() }
        // Picking a picture from the menus must not keep the keys away from the comparison.
        .onChange(of: compare.first) { refocus() }
        .onChange(of: compare.second) { refocus() }
    }

    /// Gives the keys back to the comparison. SwiftUI may still believe it has the focus while
    /// AppKit gave it away, so the focus is dropped first and taken again once the views are in place.
    private func refocus() {
        focused = false
        DispatchQueue.main.async { focused = true }
    }

    /// Two or three in a row, four as 2 × 2.
    private var sideBySide: some View {
        let count = compare.items.count
        let rows: [[Int]] = count == 4 ? [[0, 1], [2, 3]] : [Array(0..<count)]
        return VStack(spacing: 1) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(row, id: \.self) { index in
                        panel(index)
                    }
                }
            }
        }
    }

    /// All pictures at the same place. Switching shows one; blending and the divider show a pair.
    private var stacked: some View {
        let layout = compare.layout
        let (first, second) = (compare.first, compare.second)
        return GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(compare.items.indices, id: \.self) { index in
                    let visible = layout.showsPair ? (index == first || index == second) : index == compare.active
                    // Of a pair, the second lies on top and takes the mouse; the pictures are in step anyway.
                    let onTop = layout.showsPair ? index == second : index == compare.active
                    canvas(index)
                        .opacity(!visible ? 0 : layout == .blend && index == second ? compare.blend : 1)
                        .mask(alignment: .leading) {
                            if layout == .split && index == second {
                                Rectangle().padding(.leading, geometry.size.width * compare.split)
                            } else {
                                Rectangle()
                            }
                        }
                        .allowsHitTesting(onTop)
                        .zIndex(onTop ? 1 : 0)
                }
                if layout == .split {
                    SplitHandle { dx in compare.split = min(max(compare.split + dx / max(geometry.size.width, 1), 0), 1) }
                        .frame(width: 24)
                        .frame(maxHeight: .infinity)
                        .position(x: geometry.size.width * compare.split, y: geometry.size.height / 2)
                        .zIndex(2)
                }
                captions(width: geometry.size.width)
                    .zIndex(3)
            }
        }
        .overlay(alignment: .bottom) {
            controls
                .padding(.bottom, 14)
        }
    }

    /// Which picture is where: one caption, or one per picture of the pair on its side.
    @ViewBuilder private func captions(width: CGFloat) -> some View {
        if compare.layout.showsPair {
            HStack(alignment: .top) {
                floatingCaption(compare.first)
                Spacer(minLength: 12)
                floatingCaption(compare.second)
            }
            .frame(width: width)
        } else {
            floatingCaption(compare.active)
        }
    }

    private func floatingCaption(_ index: Int) -> some View {
        caption(index)
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(12)
            .allowsHitTesting(false)
    }

    private func panel(_ index: Int) -> some View {
        VStack(spacing: 0) {
            canvas(index)
            Divider()
            caption(index)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
        }
    }

    private func canvas(_ index: Int) -> some View {
        let viewer = compare.viewers[index]
        let item = compare.items[index]
        let concealed = SensitiveContentGuard.shared.isConcealed(item.url)
        let picture: CanvasPicture? = switch concealed {
        case nil: nil
        case true?: viewer.concealedPicture()
        case false?: viewer.picture
        }
        return ZStack {
            ImageCanvas(picture: picture, enlargesSmallImages: false, isPresenting: false,
                        model: viewer, gestures: CanvasGestures(),
                        onCanvas: { compare.register($0, at: index) })
            if viewer.content == nil || concealed == nil {
                ProgressView()
            } else if concealed == true {
                ConcealedOverlay(url: item.url)
            }
        }
        .task(id: item.url) {
            await SensitiveContentGuard.shared.check(item.url, isVideo: item.isVideo)
        }
    }

    /// Letter, name, dimensions and file size, so differences in resolution show at once.
    private func caption(_ index: Int) -> some View {
        let item = compare.items[index]
        let size = compare.viewers[index].picture?.size
        return HStack(spacing: 8) {
            letterBadge(index)
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(verbatim: [size.map { "\(Int($0.width)) × \(Int($0.height))" },
                            ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file)]
                .compactMap { $0 }.joined(separator: " · "))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .font(.callout)
    }

    private func letterBadge(_ index: Int) -> some View {
        Text(CompareModel.letter(index))
            .font(.headline.monospaced())
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 5))
    }

    // MARK: Controls below the pictures

    @ViewBuilder private var controls: some View {
        switch compare.layout {
        case .overlay:
            switcher
        case .blend:
            pairControls {
                // Afterwards the keys belong to the comparison again, not to the slider: Esc ends it.
                Slider(value: $compare.blend, in: 0...1) { editing in
                    if !editing { refocus() }
                }
                    .frame(width: 220)
                    .help("Überblenden: ← und → schieben in Schritten")
            }
        case .split:
            pairControls { EmptyView() }
        case .sideBySide:
            EmptyView()
        }
    }

    /// A, B, C, D as buttons to pick the picture on top.
    private var switcher: some View {
        HStack(spacing: 4) {
            ForEach(compare.items.indices, id: \.self) { index in
                Button {
                    compare.show(index)
                } label: {
                    Text(CompareModel.letter(index))
                        .font(.headline.monospaced())
                        .frame(width: 30, height: 26)
                }
                .buttonStyle(.bordered)
                .tint(index == compare.active ? .accentColor : nil)
                .help(compare.items[index].name)
            }
        }
        .padding(6)
        .background(.regularMaterial, in: Capsule())
    }

    /// The pair: which picture is first and second, a button to swap them, and what goes between.
    private func pairControls<Middle: View>(@ViewBuilder middle: () -> Middle) -> some View {
        HStack(spacing: 10) {
            pairPicker(selection: Binding(get: { compare.first }, set: { compare.show($0) }))
            middle()
            Button {
                compare.swapPair()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .buttonStyle(.borderless)
            .help("Bilder tauschen (Leertaste)")
            pairPicker(selection: Binding(get: { compare.second }, set: { compare.setSecond($0) }))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }

    /// With two pictures just the letter; with more, a menu to choose.
    @ViewBuilder private func pairPicker(selection: Binding<Int>) -> some View {
        if compare.items.count > 2 {
            Picker("Bild", selection: selection) {
                ForEach(compare.items.indices, id: \.self) { index in
                    Text(verbatim: "\(CompareModel.letter(index)) – \(compare.items[index].name)").tag(index)
                }
            }
            .labelsHidden()
            .fixedSize()
        } else {
            letterBadge(selection.wrappedValue)
        }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .ignored }
        let layout = compare.layout
        switch press.key {
        case .space where layout.showsPair:
            compare.swapPair()
        case .leftArrow where layout == .blend:
            compare.blend = max(compare.blend - 0.1, 0)
        case .rightArrow where layout == .blend:
            compare.blend = min(compare.blend + 0.1, 1)
        case .leftArrow where layout == .split:
            compare.split = max(compare.split - 0.05, 0)
        case .rightArrow where layout == .split:
            compare.split = min(compare.split + 0.05, 1)
        case .space, .rightArrow, .downArrow, .tab:
            guard layout == .overlay else { return .ignored }
            compare.showNext(press.modifiers.contains(.shift) ? -1 : 1)
        case .leftArrow, .upArrow:
            guard layout == .overlay else { return .ignored }
            compare.showNext(-1)
        case .escape:
            gallery.closeCompare()
        default:
            // 1 to 4, and A to D, pick a picture.
            let character = press.characters.lowercased()
            let index = ["1", "2", "3", "4"].firstIndex(of: character) ?? ["a", "b", "c", "d"].firstIndex(of: character)
            guard let index, index < compare.items.count else { return .ignored }
            compare.show(index)
            if layout == .sideBySide { compare.layout = .overlay }
        }
        return .handled
    }
}

/// The divider between the two pictures: a line with a knob. An AppKit view, so that it gets the
/// mouse although it lies on the pictures, which are AppKit views themselves.
private struct SplitHandle: NSViewRepresentable {
    /// Called with the horizontal movement while dragging.
    let onDrag: (CGFloat) -> Void

    func makeNSView(context: Context) -> HandleView {
        HandleView()
    }

    func updateNSView(_ view: HandleView, context: Context) {
        view.onDrag = onDrag
    }

    final class HandleView: NSView {
        var onDrag: ((CGFloat) -> Void)?

        override func draw(_ dirtyRect: NSRect) {
            let midX = bounds.midX
            NSColor.white.withAlphaComponent(0.9).setFill()
            NSRect(x: midX - 1, y: 0, width: 2, height: bounds.height).fill()
            let knob = NSRect(x: midX - 11, y: bounds.midY - 11, width: 22, height: 22)
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 3
            shadow.shadowColor = .black.withAlphaComponent(0.35)
            shadow.set()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: knob).fill()
            NSColor.secondaryLabelColor.setStroke()
            let arrows = NSBezierPath()
            arrows.move(to: NSPoint(x: knob.midX - 3, y: knob.midY - 4)); arrows.line(to: NSPoint(x: knob.midX - 6, y: knob.midY)); arrows.line(to: NSPoint(x: knob.midX - 3, y: knob.midY + 4))
            arrows.move(to: NSPoint(x: knob.midX + 3, y: knob.midY - 4)); arrows.line(to: NSPoint(x: knob.midX + 6, y: knob.midY)); arrows.line(to: NSPoint(x: knob.midX + 3, y: knob.midY + 4))
            arrows.lineWidth = 1.5
            arrows.stroke()
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        /// Where the pointer was last, in window coordinates; the movement is measured from there.
        private var lastX: CGFloat?

        override func mouseDown(with event: NSEvent) {
            lastX = event.locationInWindow.x
        }

        override func mouseDragged(with event: NSEvent) {
            let x = event.locationInWindow.x
            if let lastX { onDrag?(x - lastX) }
            lastX = x
        }

        override func mouseUp(with event: NSEvent) {
            lastX = nil
        }
    }
}
