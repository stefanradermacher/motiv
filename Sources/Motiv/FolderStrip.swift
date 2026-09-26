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

/// The folder strip above the overview, with a divider to drag it higher or lower. The height is
/// one setting for all folders and windows.
struct FolderStripSplit<Content: View>: View {
    let gallery: Gallery
    @ViewBuilder let content: Content

    @AppStorage(Preferences.folderStripHeightKey) private var height = FolderStrip.defaultHeight
    @State private var heightAtDragStart: Double?

    var body: some View {
        VStack(spacing: 0) {
            // A line below the toolbar, so the strip does not run into it.
            Divider()
            FolderStrip(gallery: gallery, height: height, resetHeight: resetHeight)
            divider
            content
        }
    }

    private func resetHeight() {
        withAnimation(.easeInOut(duration: 0.2)) { height = FolderStrip.defaultHeight }
    }

    /// A line in a band of its own, so there is something to grab: the scroll views above and
    /// below would take any click that reaches into them. A double-click restores the default height.
    private var divider: some View {
        Divider()
            .frame(maxWidth: .infinity)
            .frame(height: 9)
            .background(.background.secondary)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            // Measured in the window: the divider itself moves while it is dragged.
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { drag in
                    let start = heightAtDragStart ?? height
                    heightAtDragStart = start
                    height = min(max(start + drag.translation.height, FolderStrip.heights.lowerBound), FolderStrip.heights.upperBound)
                }
                .onEnded { _ in heightAtDragStart = nil })
            .simultaneousGesture(TapGesture(count: 2).onEnded(resetHeight))
            .help("Ziehen, um die Ordnerleiste höher oder niedriger zu machen; Doppelklick für die Standardgröße")
    }
}

/// One row above the overview with the subfolders of the folder shown, and the enclosing folder
/// first. Its height sets the size of the folder icons; they always stay in one row.
struct FolderStrip: View {
    let gallery: Gallery
    /// Height of the tiles, without a scroll bar.
    let height: CGFloat
    let resetHeight: () -> Void

    /// Icons as large as in the Finder's icon view with its standard size (64 points).
    static let defaultHeight = 64.0 + chromeHeight
    static let heights: ClosedRange<CGFloat> = 56...170
    private static let iconSizes: ClosedRange<CGFloat> = 22...128
    /// Room for the name below the icon and the paddings.
    private static let chromeHeight: CGFloat = 34

    @State private var counts: [URL: Int] = [:]
    @State private var position = ScrollPosition(edge: .leading)
    @State private var wheel = WheelScroller()

    /// Scroll bars that are always shown (the usual setting with a mouse) take height from the strip.
    /// That room is kept free even without a scroll bar, so the icons have the same size in every folder.
    private var scrollBarHeight: CGFloat {
        NSScroller.preferredScrollerStyle == .legacy ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
    }

    var body: some View {
        let iconSize = min(max(height - Self.chromeHeight, Self.iconSizes.lowerBound), Self.iconSizes.upperBound)
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 4) {
                if let parent = gallery.parentFolder {
                    FolderTile(title: FileManager.default.displayName(atPath: parent.path), count: nil,
                               help: String(localized: "Übergeordneter Ordner: \(FileManager.default.displayName(atPath: parent.path))"),
                               icon: .parent, size: iconSize) { gallery.goUp() }
                }
                ForEach(gallery.subfolders, id: \.self) { folder in
                    let name = FileManager.default.displayName(atPath: folder.path)
                    FolderTile(title: name, count: counts[folder],
                               help: counts[folder].map { String(localized: "\(name) – \($0) Bilder") } ?? name,
                               icon: .folder(folder), size: iconSize) {
                        gallery.showFolder(folder)
                        gallery.expandSidebar(toShow: folder)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(height: height, alignment: .top)
        }
        .frame(height: height + scrollBarHeight, alignment: .top)
        .scrollPosition($position)
        .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, geometry in
            wheel.offset = geometry.contentOffset.x
            wheel.maxOffset = max(0, geometry.contentSize.width - geometry.containerSize.width)
        }
        .onHover { wheel.isHovering = $0 }
        .background(.background.secondary)
        .contextMenu {
            Button("Standardgröße der Ordnerleiste", action: resetHeight)
                .disabled(height == Self.defaultHeight)
        }
        .onAppear {
            let binding = $position
            wheel.scrollTo = { binding.wrappedValue.scrollTo(x: $0) }
            wheel.start()
        }
        .onDisappear { wheel.stop() }
        .task(id: gallery.subfolders) { await count(gallery.subfolders) }
    }

    /// Counts the images and videos directly in each subfolder, one folder after the other.
    private func count(_ folders: [URL]) async {
        counts = [:]
        for folder in folders {
            let number = await Task.detached(priority: .utility) {
                let base = folder.standardizedFileURL.path
                let urls = (try? FileManager.default.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: MediaItem.resourceKeys, options: [.skipsHiddenFiles])) ?? []
                return urls.reduce(0) { $0 + (MediaItem(url: $1, base: base) == nil ? 0 : 1) }
            }.value
            guard !Task.isCancelled else { return }
            counts[folder] = number
        }
    }
}

private struct FolderTile: View {
    enum Icon {
        case parent
        case folder(URL)
    }

    let title: String
    let count: Int?
    let help: String
    let icon: Icon
    let size: CGFloat
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                image
                    .frame(width: size, height: size)
                HStack(spacing: 3) {
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let count {
                        Text(verbatim: "·")
                            .foregroundStyle(.tertiary)
                        Text(count, format: .number)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .font(.callout)
            }
            .frame(width: max(size + 40, 90))
            .padding(4)
            .background(isHovering ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
    }

    @ViewBuilder private var image: some View {
        switch icon {
        case .parent:
            // A grey folder with an arrow turning upwards (↵ turned to point up).
            Image(nsImage: NSWorkspace.shared.icon(for: .folder))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .saturation(0)
                .opacity(0.75)
                .overlay {
                    Image(systemName: "arrow.turn.left.up")
                        .resizable()
                        .scaledToFit()
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(width: size * 0.36, height: size * 0.36)
                        .offset(y: size * 0.06)
                        .shadow(color: .black.opacity(0.25), radius: 1)
                }
        case .folder(let url):
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        }
    }
}

/// Lets a vertical mouse wheel scroll the strip sideways while the pointer is over it.
@MainActor
final class WheelScroller {
    var isHovering = false
    var offset: CGFloat = 0
    var maxOffset: CGFloat = 0
    var scrollTo: ((CGFloat) -> Void)?
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            // Local monitors run on the main thread; only the numbers cross into the main actor.
            let (dx, dy, precise) = (event.scrollingDeltaX, event.scrollingDeltaY, event.hasPreciseScrollingDeltas)
            let consumed = MainActor.assumeIsolated { self?.scroll(dx: dx, dy: dy, precise: precise) ?? false }
            return consumed ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Returns whether the event was used.
    private func scroll(dx: CGFloat, dy: CGFloat, precise: Bool) -> Bool {
        // Sideways gestures on a trackpad already scroll the strip.
        guard isHovering, maxOffset > 0, abs(dy) > abs(dx) else { return false }
        let target = min(max(offset - (precise ? dy : dy * 24), 0), maxOffset)
        offset = target
        scrollTo?(target)
        return true
    }
}
