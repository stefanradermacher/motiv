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

/// The overview: all images and videos of the folder as thumbnails.
struct GridView: View {
    @Bindable var gallery: Gallery
    @AppStorage(Preferences.showNamesKey) private var showNames = true
    @FocusState private var focused: Bool
    /// What has been typed to find an item by name; cleared after a pause.
    @State private var typed = ""
    @State private var typedAt = Date.distantPast
    @State private var typedMatches = true

    private let spacing: CGFloat = 12
    /// A pause this long starts a new search, as in the Finder.
    private let typingPause: TimeInterval = 1
    private let padding: CGFloat = 20

    var body: some View {
        GeometryReader { geometry in
            let columns = columnCount(for: geometry.size.width)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: columns),
                              spacing: spacing) {
                        ForEach(gallery.items) { item in
                            cell(for: item)
                        }
                    }
                    .padding(padding)
                }
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onKeyPress(phases: [.down, .repeat]) { press in
                    handle(press, columns: columns)
                }
                .onChange(of: gallery.cursor) { _, cursor in
                    if let cursor { proxy.scrollTo(cursor) }
                }
                .onAppear {
                    focused = true
                    if let cursor = gallery.cursor { proxy.scrollTo(cursor, anchor: .center) }
                }
            }
        }
        .overlay { emptyState }
        .alert(largeScanTitle, isPresented: Binding(
            get: { gallery.confirmsLargeScan },
            set: { if !$0 && gallery.confirmsLargeScan { gallery.confirmLargeScan(false) } }
        )) {
            Button("Alle anzeigen") { gallery.confirmLargeScan(true) }
            Button("Ohne Unterordner", role: .cancel) { gallery.confirmLargeScan(false) }
        } message: {
            Text("Alle anzuzeigen kann eine Weile dauern und braucht viel Arbeitsspeicher.")
        }
        .overlay(alignment: .bottom) { typedLabel }
        .onChange(of: gallery.folder) { typed = "" }
    }

    private var largeScanTitle: String {
        String(localized: "„\(gallery.title)“ enthält mit allen Unterordnern mehr als \(Preferences.subfolderItemLimit.formatted()) Bilder und Videos.")
    }

    @ViewBuilder private var typedLabel: some View {
        if !typed.isEmpty {
            Text(typed)
                .font(.title3.weight(.medium))
                .foregroundStyle(typedMatches ? .primary : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 16)
                .transition(.opacity)
                .accessibilityLabel(Text("Suche: \(typed)"))
        }
    }

    /// Adds typed characters to the search and selects the first matching item.
    private func type(_ characters: String) {
        let now = Date()
        if now.timeIntervalSince(typedAt) > typingPause { typed = "" }
        // A space only continues a search; on its own it has no meaning in the overview.
        guard !(typed.isEmpty && characters == " ") else { return }
        typed += characters
        typedAt = now
        typedMatches = gallery.selectItem(named: typed)
        let shown = typed
        Task {
            try? await Task.sleep(for: .seconds(typingPause))
            if typed == shown { withAnimation { typed = "" } }
        }
    }

    /// Letters, digits and the like; not arrows, function keys or control characters.
    private func isTypeable(_ characters: String) -> Bool {
        !characters.isEmpty && characters.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar) && !(0xF700...0xF8FF).contains(scalar.value)
        }
    }

    private func cell(for item: MediaItem) -> some View {
        ThumbnailCell(item: item, size: gallery.thumbnailSize, isSelected: gallery.selection.contains(item.url), showsName: showNames)
            .id(item.url)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { gallery.open(item) }
            .simultaneousGesture(TapGesture().onEnded {
                gallery.click(item, modifiers: NSEvent.modifierFlags)
                focused = true
            })
            .contextMenu { ItemContextMenu(gallery: gallery, item: item) }
            .help(item.relativePath)
    }

    private func columnCount(for width: CGFloat) -> Int {
        let cellWidth = gallery.thumbnailSize + 12
        return max(1, Int((width - 2 * padding + spacing) / (cellWidth + spacing)))
    }

    private func handle(_ press: KeyPress, columns: Int) -> KeyPress.Result {
        guard press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .ignored }
        let extend = press.modifiers.contains(.shift)
        switch press.key {
        case .leftArrow: gallery.step(-1, extendingSelection: extend)
        case .rightArrow: gallery.step(1, extendingSelection: extend)
        case .upArrow: gallery.step(-columns, extendingSelection: extend)
        case .downArrow: gallery.step(columns, extendingSelection: extend)
        case .home: gallery.goToFirst(extendingSelection: extend)
        case .end: gallery.goToLast(extendingSelection: extend)
        case .return: gallery.openCursor()
        case .escape where !typed.isEmpty: typed = ""
        default:
            guard isTypeable(press.characters) else { return .ignored }
            type(press.characters)
        }
        return .handled
    }

    @ViewBuilder private var emptyState: some View {
        if gallery.confirmsLargeScan {
            EmptyView()
        } else if gallery.items.isEmpty && !gallery.isLoading {
            ContentUnavailableView {
                Label("Keine Bilder", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text(gallery.includeSubfolders
                     ? "In diesem Ordner und seinen Unterordnern liegen keine Bilder oder Videos."
                     : "In diesem Ordner liegen keine Bilder oder Videos.")
            } actions: {
                if !gallery.includeSubfolders {
                    Button("Unterordner einbeziehen") { gallery.includeSubfolders = true }
                }
            }
        } else if gallery.items.isEmpty {
            ProgressView()
        }
    }
}

struct ThumbnailCell: View {
    let item: MediaItem
    let size: CGFloat
    let isSelected: Bool
    let showsName: Bool

    var body: some View {
        VStack(spacing: 4) {
            ThumbnailImage(url: item.url, size: size)
                .overlay(alignment: .bottomLeading) {
                    if item.isVideo { VideoBadge() }
                }
                .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                .frame(width: size, height: size)
                .padding(6)
                .background(isSelected ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 8))
            if showsName {
                Text(item.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .background(isSelected ? Color.accentColor : .clear, in: Capsule())
                    .frame(maxWidth: size + 12)
            }
        }
    }
}

/// Context menu of a thumbnail. Acts on the whole selection if the item is part of it.
struct ItemContextMenu: View {
    let gallery: Gallery
    let item: MediaItem

    var body: some View {
        let urls = gallery.selection.contains(item.url) ? gallery.selectedURLs : [item.url]
        Button("Öffnen") { gallery.open(item) }
        Button("In Vorschau öffnen") { FileActions.openInPreview(urls) }
            .disabled(FileActions.previewApplication == nil)
        OpenWithMenu(urls: urls)
        Divider()
        Button("Im Finder zeigen") { FileActions.revealInFinder(urls) }
        Button("Kopieren") { FileActions.copy(urls) }
        ShareLink(items: urls) {
            Label("Teilen …", systemImage: "square.and.arrow.up")
        }
    }
}
