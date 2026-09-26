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

/// The toolbar of a window. Groups sit in capsules of their own, as in Leser and Preview.
struct GalleryToolbar: ToolbarContent {
    @Bindable var gallery: Gallery

    var body: some ToolbarContent {
        if gallery.singleFile != nil {
            ToolbarItem(placement: .navigation) {
                Button { gallery.grantFolderAccess() } label: {
                    Label("Ordner freigeben …", systemImage: "folder.badge.plus")
                        .labelStyle(.titleAndIcon)
                }
                .help("Den Ordner dieses Bildes freigeben, um alle Bilder darin zu sehen. Motiv merkt sich die Freigabe.")
            }
        }
        if gallery.mode == .compare, let compare = gallery.compare {
            ToolbarItem(placement: .navigation) {
                Button { gallery.closeCompare() } label: {
                    Label("Übersicht", systemImage: "square.grid.2x2")
                }
                .help("Vergleich beenden (Esc)")
            }
            separateItem { CompareLayoutGroup(compare: compare) }
            separateItem { CompareZoomGroup(compare: compare) }
        } else if gallery.mode == .view {
            if gallery.singleFile == nil {
                ToolbarItem(placement: .navigation) {
                    Button { gallery.closeViewer() } label: {
                        Label("Übersicht", systemImage: "square.grid.2x2")
                    }
                    .help("Zurück zur Übersicht (⌘↑)")
                }
            }
            separateItem { navigationGroup }
            separateItem { orientationGroup }
            separateItem { mirrorGroup }
            separateItem { ViewerZoomGroup(viewer: gallery.viewer) }
        } else if gallery.folder != nil {
            separateItem { ThumbnailZoomGroup(gallery: gallery) }
            separateItem { foldersGroup }
            ToolbarItem {
                Menu {
                    Picker("Sortieren nach", selection: $gallery.sortKey) {
                        ForEach(SortKey.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Toggle("Absteigend", isOn: Binding(get: { !gallery.ascending }, set: { gallery.ascending = !$0 }))
                } label: {
                    Label("Sortieren", systemImage: "arrow.up.arrow.down")
                }
                .help("Sortierung")
            }
        }
        ToolbarItem {
            Menu {
                Button("In Vorschau öffnen") { FileActions.openInPreview(gallery.targetURLs) }
                    .disabled(FileActions.previewApplication == nil)
                OpenWithMenu(urls: gallery.targetURLs)
                Divider()
                Button("Im Finder zeigen") { FileActions.revealInFinder(gallery.targetURLs) }
            } label: {
                Label("Öffnen mit", systemImage: "arrow.up.forward.app")
            }
            .disabled(gallery.targetURLs.isEmpty)
            .help("In einem anderen Programm öffnen")
        }
    }

    /// A toolbar group in its own capsule, as in Preview. With Liquid Glass (macOS 26 and later)
    /// the toolbar would otherwise put neighbouring items into one shared capsule.
    @ToolbarContentBuilder
    private func separateItem<Content: View>(@ViewBuilder _ content: () -> Content) -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem {
                content()
                    .padding(.horizontal, 4)
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem { content() }
        }
    }

    private var navigationGroup: some View {
        let gallery = gallery
        return ToolbarSegments(segments: [
            ToolbarSegment(symbol: "chevron.left", label: String(localized: "Vorheriges Bild"),
                           isEnabled: gallery.hasPrevious, action: { gallery.step(-1) }),
            ToolbarSegment(symbol: "chevron.right", label: String(localized: "Nächstes Bild"),
                           isEnabled: gallery.hasNext, action: { gallery.step(1) }),
        ])
    }

    /// Folder strip | include subfolders: two switches in one capsule; the tooltips explain them.
    private var foldersGroup: some View {
        let gallery = gallery
        return ToolbarSegments(segments: [
            ToolbarSegment(symbol: "rectangle.topthird.inset.filled",
                           label: gallery.showsFolderStrip
                               ? String(localized: "Die Leiste mit den Unterordnern über den Bildern ausblenden")
                               : String(localized: "Die Unterordner in einer Leiste über den Bildern zeigen"),
                           isSelected: gallery.showsFolderStrip,
                           action: { gallery.showsFolderStrip.toggle() }),
            ToolbarSegment(symbol: "list.bullet.indent",
                           label: gallery.includeSubfolders
                               ? String(localized: "Zeigt auch die Bilder aller Unterordner. Klicken, um nur diesen Ordner zu zeigen (⌥⌘U).")
                               : String(localized: "Zeigt nur die Bilder dieses Ordners. Klicken, um auch alle Unterordner einzubeziehen (⌥⌘U)."),
                           isSelected: gallery.includeSubfolders,
                           action: { gallery.includeSubfolders.toggle() }),
            ToolbarSegment(symbol: "rectangle.split.2x1",
                           label: gallery.canCompare
                               ? String(localized: "Ausgewählte Bilder vergleichen (⌃⌘C)")
                               : String(localized: "Zum Vergleichen zwei bis vier Bilder auswählen"),
                           isEnabled: gallery.canCompare,
                           action: { gallery.startCompare() }),
        ])
    }

    private var orientationGroup: some View {
        let viewer = gallery.viewer
        return ToolbarSegments(segments: [
            ToolbarSegment(symbol: "rotate.left", label: String(localized: "Nach links drehen"),
                           isEnabled: viewer.canTransform, action: { viewer.rotateLeft() }),
            ToolbarSegment(symbol: "rotate.right", label: String(localized: "Nach rechts drehen"),
                           isEnabled: viewer.canTransform, action: { viewer.rotateRight() }),
        ])
    }
}

extension GalleryToolbar {
    /// Mirroring only changes the view, like rotating.
    private var mirrorGroup: some View {
        let viewer = gallery.viewer
        return ToolbarSegments(segments: [
            ToolbarSegment(symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                           label: String(localized: "Horizontal spiegeln"),
                           isEnabled: viewer.canTransform, action: { viewer.flipHorizontally() }),
            ToolbarSegment(symbol: "arrow.up.and.down.righttriangle.up.righttriangle.down",
                           label: String(localized: "Vertikal spiegeln"),
                           isEnabled: viewer.canTransform, action: { viewer.flipVertically() }),
        ])
    }
}

/// Zoom out | zoom level with fit options | zoom in – like the zoom group of Leser and Preview.
private struct ViewerZoomGroup: View {
    @Bindable var viewer: ImageViewerModel

    var body: some View {
        let viewer = viewer
        let enabled = viewer.picture != nil
        ToolbarSegments(segments: [
            ToolbarSegment(symbol: "minus.magnifyingglass", label: String(localized: "Verkleinern"),
                           isEnabled: enabled, action: { viewer.zoomOut() }),
            ToolbarSegment(title: "\(Int((viewer.zoom * 100).rounded())) %", widestTitle: "8888 %", label: String(localized: "Zoomstufe"),
                           isEnabled: enabled, menu: { Self.zoomMenu(for: viewer) }),
            ToolbarSegment(symbol: "plus.magnifyingglass", label: String(localized: "Vergrößern"),
                           isEnabled: enabled, action: { viewer.zoomIn() }),
        ])
        .popover(isPresented: $viewer.requestsZoomInput, arrowEdge: .bottom) {
            ZoomInputView(viewer: viewer)
        }
    }

    static func zoomMenu(for viewer: ImageViewerModel) -> NSMenu {
        let menu = NSMenu()
        for mode in FitMode.allCases {
            menu.addItem(ActionMenuItem(mode.title, checked: viewer.fitMode == mode) { viewer.fit(mode) })
        }
        menu.addItem(ActionMenuItem(String(localized: "Originalgröße"),
                                    checked: viewer.fitMode == nil && abs(viewer.zoom - 1) < 0.001) { viewer.actualSize() })
        menu.addItem(.separator())
        for level in ImageViewerModel.menuZoomLevels where level != 1 {
            menu.addItem(ActionMenuItem("\(Int(level * 100)) %",
                                        checked: viewer.fitMode == nil && abs(viewer.zoom - level) < 0.001) { viewer.setZoom(level) })
        }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(String(localized: "Zoomstufe eingeben …")) { viewer.requestsZoomInput = true })
        return menu
    }
}

/// Small field to enter a zoom level in percent.
private struct ZoomInputView: View {
    let viewer: ImageViewerModel

    @State private var input = ""
    @FocusState private var focused: Bool

    private var level: CGFloat? {
        let text = input.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = NumberFormatter().number(from: text).map({ CGFloat(truncating: $0) }) ?? Double(text).map({ CGFloat($0) }),
              ImageViewerModel.zoomRange.contains(number / 100)
        else { return nil }
        return number / 100
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("Zoom")
            // Empty, with the current level only as a hint, so typing never appends to it.
            TextField(text: $input, prompt: Text(verbatim: "\(Int((viewer.zoom * 100).rounded()))")) {
                Text("Zoom")
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 56)
            .focused($focused)
            .onSubmit(apply)
            Text(verbatim: "%")
                .foregroundStyle(.secondary)
            Button("Anwenden", action: apply)
                .keyboardShortcut(.defaultAction)
                .disabled(level == nil)
        }
        .padding(12)
        .onAppear { focused = true }
    }

    private func apply() {
        guard let level else { return }
        viewer.setZoom(level)
        viewer.requestsZoomInput = false
    }
}

/// Smaller | size slider | larger for the thumbnails of the overview, in one capsule.
private struct ThumbnailZoomGroup: View {
    @Bindable var gallery: Gallery

    var body: some View {
        HStack(spacing: 2) {
            button("minus.magnifyingglass", "Kleinere Miniaturen (⌘-)",
                   enabled: gallery.thumbnailSize > Preferences.thumbnailSizes.lowerBound) { gallery.zoomOut() }
            Slider(value: $gallery.thumbnailSize, in: Preferences.thumbnailSizes)
                .controlSize(.small)
                .frame(width: 100)
                .help("Größe der Miniaturen")
            button("plus.magnifyingglass", "Größere Miniaturen (⌘+)",
                   enabled: gallery.thumbnailSize < Preferences.thumbnailSizes.upperBound) { gallery.zoomIn() }
        }
        // A double-click beside the buttons restores the default size, as on the folder strip's divider.
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { gallery.resetThumbnailSize() }
        .help("Doppelklick: Standardgröße der Miniaturen (⌘0)")
    }

    private func button(_ symbol: String, _ help: LocalizedStringKey, enabled: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                // As dark as the symbols of the segmented groups; dimmed when disabled.
                .foregroundStyle(enabled ? .primary : .tertiary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(Text(help))
    }
}

/// The four ways to compare, then linking zoom and position, and matching area or pixels.
private struct CompareLayoutGroup: View {
    @Bindable var compare: CompareModel

    var body: some View {
        let compare = compare
        HStack(spacing: 6) {
            ToolbarSegments(segments: [
                ToolbarSegment(symbol: compare.items.count == 4 ? "square.grid.2x2" : "rectangle.split.3x1",
                               label: String(localized: "Nebeneinander"),
                               isSelected: compare.layout == .sideBySide,
                               action: { compare.layout = .sideBySide }),
                ToolbarSegment(symbol: "square.2.layers.3d",
                               label: String(localized: "Umschalten: an derselben Stelle, mit Leertaste, Pfeiltasten oder A–D"),
                               isSelected: compare.layout == .overlay,
                               action: { compare.layout = .overlay }),
                ToolbarSegment(symbol: "circle.righthalf.filled",
                               label: String(localized: "Überblenden: ein Bild stufenlos ins andere"),
                               isSelected: compare.layout == .blend,
                               action: { compare.layout = .blend }),
                ToolbarSegment(symbol: "square.split.2x1",
                               label: String(localized: "Trennlinie: links das eine Bild, rechts das andere"),
                               isSelected: compare.layout == .split,
                               action: { compare.layout = .split }),
            ])
            ToolbarSegments(segments: [
                ToolbarSegment(symbol: compare.isLinked ? "link" : "link.badge.plus",
                               label: compare.isLinked
                                   ? String(localized: "Zoom und Ausschnitt gekoppelt; klicken, um jedes Bild einzeln zu zoomen")
                                   : String(localized: "Jedes Bild einzeln; klicken, um Zoom und Ausschnitt zu koppeln"),
                               isSelected: compare.isLinked,
                               isEnabled: !compare.layout.isStacked,
                               action: { compare.isLinked.toggle() }),
                ToolbarSegment(symbol: "1.magnifyingglass",
                               label: compare.matching == .samePixels
                                   ? String(localized: "Gleiche Pixel: alle Bilder im selben Maßstab; klicken für denselben Ausschnitt")
                                   : String(localized: "Gleicher Ausschnitt; klicken, um alle Bilder im selben Maßstab zu zeigen (gleiche Pixel)"),
                               isSelected: compare.matching == .samePixels,
                               action: { compare.matching = compare.matching == .samePixels ? .sameArea : .samePixels }),
            ])
        }
    }
}

/// Zoom out | fit all | zoom in, for all pictures of the comparison.
private struct CompareZoomGroup: View {
    let compare: CompareModel

    var body: some View {
        let compare = compare
        ToolbarSegments(segments: [
            ToolbarSegment(symbol: "minus.magnifyingglass", label: String(localized: "Verkleinern"), action: { compare.zoom(by: 1 / 1.25) }),
            ToolbarSegment(symbol: "arrow.down.right.and.arrow.up.left", label: String(localized: "Alle an Fenster anpassen"), action: { compare.fitAll() }),
            ToolbarSegment(symbol: "plus.magnifyingglass", label: String(localized: "Vergrößern"), action: { compare.zoom(by: 1.25) }),
        ])
    }
}
