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

/// Two to four pictures compared: side by side, or on top of each other to switch between them.
@MainActor @Observable
final class CompareModel {
    enum Layout: String, CaseIterable {
        /// Next to each other; four as 2 × 2.
        case sideBySide
        /// At the same place, one at a time (A/B).
        case overlay
    }

    static let itemRange = 2...4

    let items: [MediaItem]
    let viewers: [ImageViewerModel]
    var layout = Layout.sideBySide
    /// Zooming and moving one picture does the same to the others.
    var isLinked = true
    /// The picture shown on top when switching between them.
    var active = 0

    @ObservationIgnored private var canvases: [Int: WeakCanvas] = [:]
    @ObservationIgnored private var isSyncing = false
    /// The part all pictures show while in step; nil while they are fitted to the window.
    /// Switching the layout builds new views, which take it over.
    @ObservationIgnored private var sharedViewport: (center: CGPoint, widthShare: CGFloat)?

    private struct WeakCanvas {
        weak var view: ImageScrollView?
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

    /// Switching between them always keeps them in step, so that only the picture changes.
    private var keepsInStep: Bool {
        isLinked || layout == .overlay
    }

    func register(_ canvas: ImageScrollView, at index: Int) {
        canvases[index] = WeakCanvas(view: canvas)
        canvas.onViewportChange = { [weak self] view in self?.viewportChanged(in: view) }
        guard keepsInStep, let viewport = sharedViewport else { return }
        // After SwiftUI has handed the new view its picture.
        DispatchQueue.main.async { [weak canvas] in
            canvas?.follow(center: viewport.center, widthShare: viewport.widthShare)
        }
    }

    func show(_ index: Int) {
        guard viewers.indices.contains(index) else { return }
        active = index
    }

    func showNext(_ offset: Int = 1) {
        active = (active + offset + items.count) % items.count
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
    func fitAll() { views.forEach { $0.fitAutomatically() } }

    // MARK: Keeping in step

    /// When one picture is zoomed or moved, the others show the same part of theirs. A fitted
    /// picture makes the others fit too.
    private func viewportChanged(in source: ImageScrollView) {
        guard keepsInStep, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        let others = views.filter { $0 !== source }
        if source.fitMode == .window {
            sharedViewport = nil
            others.filter { $0.fitMode != .window }.forEach { $0.fitAutomatically() }
        } else if let viewport = source.viewport {
            sharedViewport = viewport
            others.forEach { $0.follow(center: viewport.center, widthShare: viewport.widthShare) }
        }
    }

    /// After switching the layout or linking, bring the others in line with the picture on top.
    func alignToActive() {
        guard let source = canvases[active]?.view else { return }
        viewportChanged(in: source)
    }
}

/// The comparison: the pictures with their names, dimensions and sizes.
struct CompareView: View {
    @Bindable var gallery: Gallery
    let compare: CompareModel
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            switch compare.layout {
            case .sideBySide:
                sideBySide
            case .overlay:
                overlay
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: [.down, .repeat]) { press in handle(press) }
        .onExitCommand { gallery.closeCompare() }
        .onAppear { focused = true }
        .onChange(of: compare.layout) { compare.alignToActive() }
        .onChange(of: compare.isLinked) { compare.alignToActive() }
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

    /// All pictures at the same place; only the active one is visible and takes the mouse.
    private var overlay: some View {
        ZStack(alignment: .topLeading) {
            ForEach(compare.items.indices, id: \.self) { index in
                canvas(index)
                    .opacity(index == compare.active ? 1 : 0)
                    .allowsHitTesting(index == compare.active)
            }
            caption(compare.active)
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(12)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            switcher
                .padding(.bottom, 14)
        }
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
            Text(CompareModel.letter(index))
                .font(.headline.monospaced())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 5))
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

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .ignored }
        switch press.key {
        case .space, .rightArrow, .downArrow, .tab:
            guard compare.layout == .overlay else { return .ignored }
            compare.showNext(press.modifiers.contains(.shift) ? -1 : 1)
        case .leftArrow, .upArrow:
            guard compare.layout == .overlay else { return .ignored }
            compare.showNext(-1)
        case .escape:
            gallery.closeCompare()
        default:
            // 1 to 4, and A to D, pick a picture.
            let character = press.characters.lowercased()
            let index = ["1", "2", "3", "4"].firstIndex(of: character) ?? ["a", "b", "c", "d"].firstIndex(of: character)
            guard let index, index < compare.items.count else { return .ignored }
            compare.show(index)
            if compare.layout == .sideBySide { compare.layout = .overlay }
        }
        return .handled
    }
}
