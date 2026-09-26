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

/// The images of the folder as a list in the sidebar. Choosing one, with the mouse or the arrow
/// keys, shows it in the single-image view next to the list.
struct ImageList: View {
    let gallery: Gallery

    var body: some View {
        let groups = Self.groups(of: gallery.items)
        ScrollViewReader { proxy in
            List(selection: Binding(
                get: { gallery.mode == .view ? gallery.current : gallery.cursor },
                set: { url in if let url { gallery.show(url) } }
            )) {
                if let groups {
                    ForEach(groups, id: \.folder) { group in
                        Section(group.folder.isEmpty ? gallery.title : group.folder) {
                            ForEach(group.items) { ImageRow(item: $0, showsFolder: false) }
                        }
                    }
                } else {
                    ForEach(gallery.items) { ImageRow(item: $0, showsFolder: gallery.includeSubfolders) }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if gallery.items.isEmpty && !gallery.isLoading {
                    ContentUnavailableView("Keine Bilder", systemImage: "photo")
                }
            }
            .onChange(of: gallery.current, initial: true) { _, current in
                if let current { proxy.scrollTo(current) }
            }
        }
    }

    struct Group {
        let folder: String
        let items: [MediaItem]
    }

    /// Items by subfolder, if each subfolder forms one run in the current order (as when sorted
    /// by name). Otherwise, e.g. when sorted by date, subfolders would be torn apart: nil.
    static func groups(of items: [MediaItem]) -> [Group]? {
        var groups: [Group] = []
        var seen: Set<String> = []
        var current: (folder: String, items: [MediaItem])?
        for item in items {
            let folder = item.folderPath
            if current?.folder == folder {
                current?.items.append(item)
                continue
            }
            if let current { groups.append(Group(folder: current.folder, items: current.items)) }
            guard seen.insert(folder).inserted else { return nil }
            current = (folder, [item])
        }
        if let current { groups.append(Group(folder: current.folder, items: current.items)) }
        return groups.count > 1 ? groups : nil
    }
}

private struct ImageRow: View {
    let item: MediaItem
    let showsFolder: Bool

    var body: some View {
        HStack(spacing: 8) {
            ThumbnailImage(url: item.url, size: 36, isVideo: item.isVideo)
                .overlay(alignment: .bottomLeading) {
                    if item.isVideo {
                        Image(systemName: "play.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(.white)
                            .padding(2)
                            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 2))
                    }
                }
                .frame(width: 40, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(showsFolder && !item.folderPath.isEmpty ? item.folderPath : ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .tag(item.url)
        .id(item.url)
        .help(item.relativePath)
    }
}

extension MediaItem {
    /// The subfolder the item lies in, relative to the folder shown; empty for the folder itself.
    var folderPath: String {
        (relativePath as NSString).deletingLastPathComponent
    }
}
