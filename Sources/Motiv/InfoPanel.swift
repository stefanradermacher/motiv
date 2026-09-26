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

/// Information about the image shown or selected, in the sidebar.
struct InfoPanel: View {
    let gallery: Gallery

    var body: some View {
        let items = gallery.infoItems
        switch items.count {
        case 0:
            ContentUnavailableView("Kein Bild ausgewählt", systemImage: "info.circle",
                                   description: Text("Wähle ein Bild aus, um seine Informationen zu sehen."))
        case 1:
            ItemInfoView(item: items[0])
                .id(items[0].url)
        default:
            SelectionSummary(items: items)
        }
    }
}

/// Several items selected: how many, and how large together.
private struct SelectionSummary: View {
    let items: [MediaItem]

    var body: some View {
        let size = items.reduce(0) { $0 + $1.size }
        let videos = items.filter(\.isVideo).count
        VStack(spacing: 6) {
            Image(systemName: "photo.stack")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("\(items.count) Objekte ausgewählt")
                .font(.headline)
            Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                .foregroundStyle(.secondary)
            if videos > 0 {
                Text("davon \(videos) Videos")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct ItemInfoView: View {
    let item: MediaItem

    @State private var info: ImageInfo?
    @State private var filter = ""
    @AppStorage("infoCollapsed") private var collapsedStorage = "all"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ThumbnailImage(url: item.url, size: 200)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                if let info {
                    ForEach(info.sections) { section in
                        disclosure(section.title, key: section.kind.rawValue) {
                            entries(section.entries)
                            if section.kind == .location, let url = info.mapsURL {
                                Button {
                                    NSWorkspace.shared.open(url)
                                } label: {
                                    Label("In Karten öffnen", systemImage: "map")
                                }
                                .controlSize(.small)
                                .padding(.top, 2)
                            }
                        }
                    }
                    if !info.allMetadata.isEmpty {
                        disclosure(String(localized: "Alle Metadaten"), key: "all") {
                            TextField("Filtern", text: $filter)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                            entries(info.allMetadata.filter {
                                filter.isEmpty || $0.label.localizedCaseInsensitiveContains(filter)
                                    || $0.value.localizedCaseInsensitiveContains(filter)
                            }, compact: true)
                            Button("Alle kopieren") { copy(info.allMetadata) }
                                .controlSize(.small)
                        }
                    }
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .task(id: item.url) {
            info = ImageInfoCache.shared.cached(item.url)
            if info == nil { info = await ImageInfoCache.shared.info(for: item) }
        }
    }

    // MARK: Parts

    private func disclosure<Content: View>(_ title: String, key: String, @ViewBuilder content: () -> Content) -> some View {
        let content = content()
        return DisclosureGroup(isExpanded: expansion(key)) {
            VStack(alignment: .leading, spacing: 6) { content }
                .padding(.top, 6)
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func entries(_ entries: [InfoEntry], compact: Bool = false) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: compact ? 3 : 5) {
            ForEach(entries) { entry in
                GridRow {
                    Text(entry.label)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: compact ? 130 : 110, alignment: .trailing)
                    Text(entry.value)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(compact ? .caption : .callout)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Sections are expanded, except "All metadata"; what the user collapses stays collapsed.
    private func expansion(_ key: String) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(key) },
            set: { expanded in
                var set = collapsed
                if expanded { set.remove(key) } else { set.insert(key) }
                collapsedStorage = set.sorted().joined(separator: ",")
            }
        )
    }

    private var collapsed: Set<String> {
        Set(collapsedStorage.split(separator: ",").map(String.init))
    }

    private func copy(_ entries: [InfoEntry]) {
        let text = entries.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// A line at the bottom of the single-image view with the most important facts.
struct QuickInfoBar: View {
    let item: MediaItem

    @State private var summary = ""

    var body: some View {
        // Always present, only hidden while empty: an empty view would never run its task.
        Text(summary)
            .font(.callout)
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 10)
            .textSelection(.enabled)
            .opacity(summary.isEmpty ? 0 : 1)
            .task(id: item.url) {
            summary = ImageInfoCache.shared.cached(item.url)?.summary ?? summary
            summary = await ImageInfoCache.shared.info(for: item).summary
        }
    }
}
