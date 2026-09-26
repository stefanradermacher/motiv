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

/// A row in the sidebar. Favourites and folders get their own identity, so that a folder that is
/// also a favourite does not appear twice under one tag.
enum SidebarItem: Hashable {
    case favorite(URL)
    case folder(URL)

    var url: URL {
        switch self {
        case .favorite(let url), .folder(let url): url
        }
    }
}

/// The sidebar: folders, information about the image, or both, one above the other.
struct SidebarView: View {
    @Bindable var gallery: Gallery

    var body: some View {
        VStack(spacing: 0) {
            Picker("Seitenleiste", selection: $gallery.sidebarContent) {
                ForEach(SidebarContent.allCases) { content in
                    Image(systemName: content.systemImage)
                        .accessibilityLabel(content.title)
                        .help(content.title)
                        .tag(content)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            switch gallery.sidebarContent {
            case .folders:
                FolderList(gallery: gallery)
            case .images:
                ImageList(gallery: gallery)
            case .info:
                InfoPanel(gallery: gallery)
            case .both:
                VSplitView {
                    FolderList(gallery: gallery)
                        .frame(minHeight: 120)
                    InfoPanel(gallery: gallery)
                        .frame(minHeight: 160)
                }
            }
        }
    }
}

/// Favourites and the tree of granted folders.
struct FolderList: View {
    @Bindable var gallery: Gallery
    @State private var selection: SidebarItem?
    private let library = Library.shared

    var body: some View {
        List(selection: Binding(get: { selection }, set: select)) {
            if !library.favorites.isEmpty {
                Section("Favoriten") {
                    ForEach(library.favorites) { place in
                        if library.unavailable.contains(place.path) {
                            UnavailableRow(place: place, isFavorite: true)
                        } else {
                            RemovableRow(removeHelp: "Aus Favoriten entfernen", remove: { removeFavorite(place) }) {
                                Label(place.name, systemImage: "star")
                            }
                            .tag(SidebarItem.favorite(place.url))
                            .contextMenu { FolderContextMenu(url: place.url, gallery: gallery) }
                        }
                    }
                }
            }
            Section("Ordner") {
                ForEach(library.rootNodes) { node in
                    FolderRow(node: node, gallery: gallery)
                }
                ForEach(library.roots.filter { library.unavailable.contains($0.path) }) { place in
                    UnavailableRow(place: place, isFavorite: false)
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: gallery.folder, initial: true) { _, folder in
            // Follows folders chosen elsewhere, e.g. from the Finder or with ⌘↑.
            if selection?.url != folder { selection = folder.map(SidebarItem.folder) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Button {
                    if let folder = library.chooseFolders().first { gallery.showFolder(folder) }
                } label: {
                    Label("Ordner hinzufügen …", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .help("Ordner hinzufügen (⌘O)")
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func select(_ item: SidebarItem?) {
        selection = item
        if let item { gallery.showFolder(item.url) }
    }

    private func removeFavorite(_ place: Place) {
        library.removeFavorite(place)
        gallery.closeFolderIfUnreadable()
    }
}

/// Shows a remove button at the trailing edge while the pointer is over the row.
struct RemovableRow<Content: View>: View {
    let removeHelp: LocalizedStringKey
    let remove: () -> Void
    @ViewBuilder let content: Content
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            content
            Spacer(minLength: 0)
            if isHovering {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(removeHelp)
                .accessibilityLabel(Text(removeHelp))
            }
        }
        .onHover { isHovering = $0 }
    }
}

/// A folder and, when expanded, its subfolders.
private struct FolderRow: View {
    let node: FolderNode
    let gallery: Gallery

    var body: some View {
        if let children = node.children {
            DisclosureGroup(isExpanded: expansion) {
                ForEach(children) { FolderRow(node: $0, gallery: gallery) }
            } label: {
                label
            }
        } else {
            label
        }
    }

    @ViewBuilder private var label: some View {
        let library = Library.shared
        if let root = library.roots.first(where: { $0.path == node.url.path }) {
            RemovableRow(removeHelp: "Aus der Seitenleiste entfernen", remove: {
                library.remove(root)
                gallery.closeFolderIfUnreadable()
            }) {
                if root.isTemporary {
                    Label(node.name, systemImage: "hourglass")
                        .help("Nur bis zum Beenden von Motiv freigegeben")
                } else {
                    Label(node.name, systemImage: "externaldrive")
                }
            }
            .tag(SidebarItem.folder(node.url))
            .contextMenu { FolderContextMenu(url: node.url, gallery: gallery) }
        } else {
            Label(node.name, systemImage: "folder")
                .tag(SidebarItem.folder(node.url))
                .contextMenu { FolderContextMenu(url: node.url, gallery: gallery) }
        }
    }

    private var expansion: Binding<Bool> {
        Binding(
            get: { gallery.expanded.contains(node.url) },
            set: { if $0 { gallery.expanded.insert(node.url) } else { gallery.expanded.remove(node.url) } }
        )
    }
}

/// A folder whose bookmark no longer resolves, for example on a disk that is not connected.
private struct UnavailableRow: View {
    let place: Place
    let isFavorite: Bool

    var body: some View {
        RemovableRow(removeHelp: isFavorite ? "Aus Favoriten entfernen" : "Aus der Seitenleiste entfernen", remove: remove) {
            Label(place.name, systemImage: "exclamationmark.triangle")
        }
            .foregroundStyle(.secondary)
            .selectionDisabled()
            .help("Motiv kann diesen Ordner derzeit nicht lesen.")
            .contextMenu {
                Button("Erneut freigeben …") { Library.shared.grantAgain(place) }
                Button(isFavorite ? "Aus Favoriten entfernen" : "Aus der Seitenleiste entfernen", action: remove)
            }
    }

    private func remove() {
        if isFavorite { Library.shared.removeFavorite(place) } else { Library.shared.remove(place) }
    }
}

struct FolderContextMenu: View {
    let url: URL
    let gallery: Gallery

    var body: some View {
        let library = Library.shared
        Button(library.isFavorite(url) ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen") {
            library.toggleFavorite(url)
            gallery.closeFolderIfUnreadable()
        }
        Button("Im Finder zeigen") { FileActions.revealInFinder([url]) }
        if let root = library.roots.first(where: { $0.path == url.folderURL.path }) {
            Divider()
            if root.isTemporary {
                Button("Dauerhaft behalten") { library.keep(root) }
            }
            Button("Aus der Seitenleiste entfernen") {
                library.remove(root)
                gallery.closeFolderIfUnreadable()
            }
        }
    }
}
