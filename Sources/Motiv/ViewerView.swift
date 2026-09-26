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

import SwiftUI

/// The single-image view with the filmstrip below.
struct ViewerView: View {
    @Bindable var gallery: Gallery
    @AppStorage(Preferences.enlargeSmallImagesKey) private var enlargesSmallImages = false
    @FocusState private var focused: Bool

    private var viewer: ImageViewerModel { gallery.viewer }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ImageCanvas(picture: shownPicture, enlargesSmallImages: enlargesSmallImages,
                            isPresenting: gallery.isPresenting, model: viewer, gestures: gestures)
                overlay
            }
            .overlay(alignment: .bottom) {
                if gallery.showsQuickInfo && !gallery.isPresenting, let item = viewer.item {
                    QuickInfoBar(item: item)
                }
            }
            if gallery.showsFilmstripNow {
                Divider()
                Filmstrip(gallery: gallery)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: [.down, .repeat]) { press in handle(press) }
        .onExitCommand(perform: leave)
        .task(id: "\(viewer.item?.url.path ?? "")|\(SensitiveContentGuard.shared.isBlurring)") {
            guard let item = viewer.item else { return }
            await SensitiveContentGuard.shared.check(item.url, isVideo: item.isVideo)
        }
        .onAppear { focused = true }
    }

    private var gestures: CanvasGestures {
        let gallery = gallery
        let viewer = viewer
        return CanvasGestures(
            hasPrevious: gallery.hasPrevious,
            hasNext: gallery.hasNext,
            canRotate: viewer.canTransform && concealed == false,
            step: { gallery.step($0) },
            rotate: { $0 > 0 ? viewer.rotateRight() : viewer.rotateLeft() }
        )
    }

    /// Whether the picture shown is hidden as possibly sensitive; nil while it is being checked.
    private var concealed: Bool? {
        viewer.item.map { SensitiveContentGuard.shared.isConcealed($0.url) } ?? false
    }

    /// Nothing until the check is done, so that a sensitive picture never flashes up.
    private var shownPicture: CanvasPicture? {
        switch concealed {
        case nil: nil
        case true?: viewer.concealedPicture()
        case false?: viewer.picture
        }
    }

    @ViewBuilder private var overlay: some View {
        if let item = viewer.item, concealed != false {
            if concealed == true { ConcealedOverlay(url: item.url) } else { ProgressView() }
        } else {
            contentOverlay
        }
    }

    @ViewBuilder private var contentOverlay: some View {
        switch viewer.content {
        case nil:
            ProgressView()
        case .failed:
            ContentUnavailableView("Die Datei lässt sich nicht anzeigen", systemImage: "exclamationmark.triangle",
                                   description: Text(viewer.item?.name ?? ""))
        case .poster:
            if let item = viewer.item { VideoOverlay(url: item.url) }
        default:
            EmptyView()
        }
    }

    /// Esc ends showing only the image first, then the single-image view.
    private func leave() {
        if gallery.isPresenting { gallery.stopPresenting() } else { gallery.closeViewer() }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .ignored }
        switch press.key {
        // Up and down as well, to match the image list in the sidebar.
        case .leftArrow, .upArrow, .pageUp: gallery.step(-1)
        case .rightArrow, .downArrow, .pageDown, .space: gallery.step(1)
        case .home: gallery.goToFirst()
        case .end: gallery.goToLast()
        case .escape: leave()
        default: return .ignored
        }
        return .handled
    }
}

/// Shown on top of the still frame of a video.
struct VideoOverlay: View {
    let url: URL

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "play.circle")
                .font(.system(size: 52, weight: .light))
            Text("Videos spielt Motiv nicht selbst ab.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(openTitle) { FileActions.openWithDefaultApp(url) }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var openTitle: String {
        guard let app = FileActions.defaultApplication(for: url) else { return String(localized: "Öffnen") }
        return String(localized: "In \(FileActions.name(of: app)) öffnen")
    }
}

/// A row of small thumbnails of the folder; the current image is highlighted.
struct Filmstrip: View {
    let gallery: Gallery

    private let size: CGFloat = 56

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 6) {
                    ForEach(gallery.items) { item in
                        let isCurrent = item.url == gallery.current
                        ThumbnailImage(url: item.url, size: size, isVideo: item.isVideo)
                            .overlay(alignment: .bottomLeading) {
                                if item.isVideo { VideoBadge().scaleEffect(0.8, anchor: .bottomLeading) }
                            }
                            .frame(width: size, height: size)
                            .padding(4)
                            .background(isCurrent ? Color.accentColor.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                            .onTapGesture { gallery.show(item.url) }
                            .help(item.relativePath)
                            .id(item.url)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .frame(height: size + 20)
            .background(.bar)
            .onChange(of: gallery.current, initial: true) { _, current in
                guard let current else { return }
                withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(current, anchor: .center) }
            }
        }
    }
}
