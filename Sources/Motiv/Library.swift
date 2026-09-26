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

/// A folder the user granted access to, kept across launches as a security-scoped bookmark.
struct Place: Identifiable, Hashable, Codable {
    var path: String
    var bookmark: Data

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
    var name: String { FileManager.default.displayName(atPath: path) }
}

/// The folders shown in the sidebar and the favourites.
///
/// In the sandbox, Motiv may only read what the user chose. Opening a single image does not
/// allow reading the images next to it, so Motiv works with whole folders: the user grants a
/// folder once, and Motiv keeps a bookmark to it. Everything below that folder is then readable.
@MainActor @Observable
final class Library {
    static let shared = Library()

    private(set) var roots: [Place] = []
    private(set) var favorites: [Place] = []
    /// Tree nodes of the roots that can be read.
    private(set) var rootNodes: [FolderNode] = []
    /// Paths of places whose bookmark no longer resolves, for example because the disk is
    /// not connected. They have to be granted again.
    private(set) var unavailable: Set<String> = []

    @ObservationIgnored private var accessedRoots: [String: URL] = [:]
    @ObservationIgnored private var accessedFavorites: [String: URL] = [:]

    private static let rootsKey = "folders"
    private static let favoritesKey = "favorites"

    private init() {
        roots = Self.load(Self.rootsKey).map { resolve($0, into: &accessedRoots) }
        favorites = Self.load(Self.favoritesKey).map { resolve($0, into: &accessedFavorites) }
        save()
        rebuildNodes()
    }

    // MARK: Roots

    /// Asks for one or more folders and adds them. Returns the folders added.
    @discardableResult
    func chooseFolders() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Hinzufügen")
        panel.message = String(localized: "Wähle Ordner mit Bildern. Motiv merkt sich die Freigabe und zeigt die Ordner in der Seitenleiste.")
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { add($0) }
    }

    /// Asks for the folder of a file opened from the Finder. Returns whether Motiv may now
    /// read the file's folder.
    func requestAccess(toFolderOf file: URL) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.directoryURL = file.deletingLastPathComponent()
        panel.prompt = String(localized: "Zugriff erlauben")
        panel.message = String(localized: "Ordner freigeben, um alle Bilder darin zu sehen")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        add(url)
        return contains(file)
    }

    /// Asks again for a folder whose bookmark no longer resolves.
    func grantAgain(_ place: Place) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = place.url.deletingLastPathComponent()
        panel.prompt = String(localized: "Zugriff erlauben")
        panel.message = String(localized: "Wähle den Ordner „\(place.name)“ erneut aus.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if url.folderURL.path != place.path { remove(place) }
        add(url)
    }

    /// Adds a folder the user chose or dropped. Returns it in canonical form.
    @discardableResult
    func add(_ url: URL) -> URL? {
        let folder = url.folderURL
        let path = folder.path
        if let index = roots.firstIndex(where: { $0.path == path }) {
            guard unavailable.contains(path) else { return folder }
            roots.remove(at: index)
        }
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return nil }
        unavailable.remove(path)
        if accessedRoots[path] == nil, url.startAccessingSecurityScopedResource() {
            accessedRoots[path] = url
        }
        roots.append(Place(path: path, bookmark: bookmark))
        roots.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        save()
        rebuildNodes()
        return folder
    }

    func remove(_ place: Place) {
        roots.removeAll { $0.path == place.path }
        accessedRoots.removeValue(forKey: place.path)?.stopAccessingSecurityScopedResource()
        if !favorites.contains(where: { $0.path == place.path }) { unavailable.remove(place.path) }
        save()
        rebuildNodes()
    }

    func isRoot(_ url: URL) -> Bool {
        roots.contains { $0.path == url.folderURL.path }
    }

    /// The readable root that contains `url`.
    func root(containing url: URL) -> Place? {
        roots.first { !unavailable.contains($0.path) && $0.url.contains(url) }
    }

    /// Whether Motiv may read `url`: it lies in a readable root or favourite.
    func contains(_ url: URL) -> Bool {
        (roots + favorites).contains { !unavailable.contains($0.path) && $0.url.contains(url) }
    }

    /// Reads the folder tree again, for example after folders were added in the Finder.
    func refresh() {
        rebuildNodes()
    }

    // MARK: Favorites

    func isFavorite(_ url: URL) -> Bool {
        favorites.contains { $0.path == url.folderURL.path }
    }

    func toggleFavorite(_ url: URL) {
        let folder = url.folderURL
        if let index = favorites.firstIndex(where: { $0.path == folder.path }) {
            let place = favorites.remove(at: index)
            accessedFavorites.removeValue(forKey: place.path)?.stopAccessingSecurityScopedResource()
            if !roots.contains(where: { $0.path == place.path }) { unavailable.remove(place.path) }
        } else {
            // A bookmark of its own keeps the favourite readable even if its root is removed.
            guard let bookmark = try? folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            else { return }
            favorites.append(Place(path: folder.path, bookmark: bookmark))
        }
        save()
    }

    func removeFavorite(_ place: Place) {
        toggleFavorite(place.url)
    }

    // MARK: Storage

    /// Resolves the bookmark, starts access and returns the place with its current path;
    /// the folder may have been renamed or moved in the meantime.
    private func resolve(_ place: Place, into accessed: inout [String: URL]) -> Place {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: place.bookmark, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource()
        else {
            unavailable.insert(place.path)
            return place
        }
        var resolved = place
        resolved.path = url.folderURL.path
        accessed[resolved.path] = url
        if stale, let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            resolved.bookmark = bookmark
        }
        return resolved
    }

    private func rebuildNodes() {
        rootNodes = roots.filter { !unavailable.contains($0.path) }.map { FolderNode(url: $0.url) }
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(try? JSONEncoder().encode(roots), forKey: Self.rootsKey)
        defaults.set(try? JSONEncoder().encode(favorites), forKey: Self.favoritesKey)
    }

    private static func load(_ key: String) -> [Place] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Place].self, from: data)) ?? []
    }
}

/// A folder in the sidebar tree. Subfolders are read from disk the first time they are needed.
final class FolderNode: Identifiable {
    let url: URL
    let name: String

    var id: URL { url }

    init(url: URL) {
        self.url = url.folderURL
        name = FileManager.default.displayName(atPath: url.path)
    }

    /// nil if the folder has no subfolders, so the sidebar shows no disclosure triangle.
    private(set) lazy var children: [FolderNode]? = {
        let subfolders = FolderNode.subfolders(of: url)
        return subfolders.isEmpty ? nil : subfolders.map(FolderNode.init)
    }()

    static func subfolders(of url: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        else { return [] }
        return contents
            .filter {
                let values = try? $0.resourceValues(forKeys: keys)
                return values?.isDirectory == true && values?.isPackage != true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
