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
import UniformTypeIdentifiers

/// An image or video in the folder shown.
struct MediaItem: Identifiable, Hashable {
    let url: URL
    /// Path relative to the folder shown. Differs from the file name for items in subfolders.
    let relativePath: String
    let date: Date
    let size: Int
    let type: UTType

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var isVideo: Bool { type.conforms(to: .movie) }

    static let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .contentTypeKey, .contentModificationDateKey, .fileSizeKey]

    /// nil for anything that is neither an image nor a video.
    init?(url: URL, base: String) {
        guard let values = try? url.resourceValues(forKeys: Set(Self.resourceKeys)),
              values.isRegularFile == true,
              let type = values.contentType,
              type.conforms(to: .image) || type.conforms(to: .movie)
        else { return nil }
        let path = url.standardizedFileURL.path
        self.url = url
        relativePath = path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : url.lastPathComponent
        date = values.contentModificationDate ?? .distantPast
        size = values.fileSize ?? 0
        self.type = type
    }
}

/// What the sidebar shows. Each mode of the window remembers its own choice, so the overview
/// usually shows the folders and the single-image view the information.
enum SidebarContent: String, CaseIterable, Identifiable {
    case folders, images, info, both

    var id: Self { self }

    var title: String {
        switch self {
        case .folders: String(localized: "Ordner")
        case .images: String(localized: "Bilder")
        case .info: String(localized: "Informationen")
        case .both: String(localized: "Ordner und Informationen")
        }
    }

    var systemImage: String {
        switch self {
        case .folders: "folder"
        case .images: "photo.on.rectangle"
        case .info: "info.circle"
        case .both: "rectangle.split.1x2"
        }
    }
}

enum SortKey: String, CaseIterable, Identifiable {
    case name, captureDate, date, size, kind

    var id: Self { self }

    var title: String {
        switch self {
        case .name: String(localized: "Name")
        case .captureDate: String(localized: "Aufnahmedatum")
        case .date: String(localized: "Änderungsdatum")
        case .size: String(localized: "Größe")
        case .kind: String(localized: "Art")
        }
    }
}

/// What one window shows: a folder as a grid of thumbnails, or one of its images.
@MainActor @Observable
final class Gallery {
    enum Mode {
        case browse, view
    }

    /// The folder shown, chosen in the sidebar.
    private(set) var folder: URL?
    /// A single file opened from the Finder whose folder Motiv may not read.
    private(set) var singleFile: URL?
    private(set) var items: [MediaItem] = []
    private(set) var isLoading = false
    var selection: Set<URL> = []
    /// Where keyboard navigation starts: the item clicked or moved to last.
    private(set) var cursor: URL?
    private(set) var mode = Mode.browse
    /// The item in the single-image view.
    private(set) var current: URL?
    /// Folders expanded in the sidebar.
    var expanded: Set<URL> = []

    var includeSubfolders = UserDefaults.standard.bool(forKey: Preferences.includeSubfoldersKey) {
        didSet {
            UserDefaults.standard.set(includeSubfolders, forKey: Preferences.includeSubfoldersKey)
            reload()
        }
    }
    var sortKey = Preferences.sortKey {
        didSet {
            UserDefaults.standard.set(sortKey.rawValue, forKey: Preferences.sortKeyKey)
            items = sorted(items)
            readCaptureDatesIfNeeded()
        }
    }
    var ascending = UserDefaults.standard.bool(forKey: Preferences.sortAscendingKey) {
        didSet {
            UserDefaults.standard.set(ascending, forKey: Preferences.sortAscendingKey)
            items = sorted(items)
        }
    }
    var thumbnailSize = UserDefaults.standard.double(forKey: Preferences.thumbnailSizeKey) {
        didSet { UserDefaults.standard.set(thumbnailSize, forKey: Preferences.thumbnailSizeKey) }
    }
    var showsFilmstrip = UserDefaults.standard.bool(forKey: Preferences.showsFilmstripKey) {
        didSet { UserDefaults.standard.set(showsFilmstrip, forKey: Preferences.showsFilmstripKey) }
    }

    var showsQuickInfo = UserDefaults.standard.bool(forKey: Preferences.showsQuickInfoKey) {
        didSet { UserDefaults.standard.set(showsQuickInfo, forKey: Preferences.showsQuickInfoKey) }
    }
    private var sidebarContentForBrowsing = SidebarContent(rawValue: UserDefaults.standard.string(forKey: Preferences.sidebarBrowseKey) ?? "") ?? .folders {
        didSet { UserDefaults.standard.set(sidebarContentForBrowsing.rawValue, forKey: Preferences.sidebarBrowseKey) }
    }
    private var sidebarContentForViewing = SidebarContent(rawValue: UserDefaults.standard.string(forKey: Preferences.sidebarViewKey) ?? "") ?? .info {
        didSet { UserDefaults.standard.set(sidebarContentForViewing.rawValue, forKey: Preferences.sidebarViewKey) }
    }
    /// Whether the sidebar is shown; set by the sidebar commands too.
    var columnVisibility = NavigationSplitViewVisibility.automatic
    /// Only the image, full screen, without toolbar, sidebar and filmstrip.
    private(set) var isPresenting = false
    /// Capture dates read so far, for sorting by them. Files without one sort by their modification date.
    @ObservationIgnored private var captureDates: [URL: Date] = [:]
    private(set) var isReadingCaptureDates = false
    @ObservationIgnored private var captureDateTask: Task<Void, Never>?

    /// The folders directly inside the folder shown, for the folder strip above the overview.
    private(set) var subfolders: [URL] = []
    @ObservationIgnored private var subfolderTask: Task<Void, Never>?
    var showsFolderStrip = UserDefaults.standard.bool(forKey: Preferences.showsFolderStripKey) {
        didSet { UserDefaults.standard.set(showsFolderStrip, forKey: Preferences.showsFolderStripKey) }
    }

    let viewer = ImageViewerModel()

    /// What the sidebar shows in the current mode.
    var sidebarContent: SidebarContent {
        get { mode == .view ? sidebarContentForViewing : sidebarContentForBrowsing }
        set {
            if mode == .view { sidebarContentForViewing = newValue } else { sidebarContentForBrowsing = newValue }
            if columnVisibility == .detailOnly { columnVisibility = .all }
        }
    }

    /// Shows or hides the information, keeping the folders as they are.
    func toggleInfo() {
        if columnVisibility == .detailOnly {
            // A hidden sidebar comes back with the information.
            columnVisibility = .all
            if sidebarContent != .info && sidebarContent != .both { sidebarContent = .info }
            return
        }
        sidebarContent = sidebarContent == .info || sidebarContent == .both ? .folders : .info
    }

    /// The filmstrip shows the same as the image list; with the list visible it is left out.
    var showsFilmstripNow: Bool {
        showsFilmstrip && items.count > 1 && !isPresenting
            && !(sidebarContent == .images && columnVisibility != .detailOnly)
    }

    /// The items the information describes: the image shown, or the selection in the overview.
    var infoItems: [MediaItem] {
        if mode == .view { return current.flatMap(item(for:)).map { [$0] } ?? [] }
        return items.filter { selection.contains($0.url) }
    }

    /// Fixed end of a range selected with shift.
    @ObservationIgnored private var anchor: URL?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// A file to show once the folder has been read.
    @ObservationIgnored private var pendingReveal: URL?
    /// The user agreed to show a very large folder tree anyway.
    @ObservationIgnored private var allowsLargeScan = false
    /// Set when the folder with its subfolders holds more than `Preferences.subfolderItemLimit`
    /// items; the overview then asks before reading them all.
    var confirmsLargeScan = false

    // MARK: Title

    var title: String {
        if let singleFile { return singleFile.lastPathComponent }
        if let folder { return FileManager.default.displayName(atPath: folder.path) }
        return "Motiv"
    }

    var subtitle: String {
        if singleFile != nil { return String(localized: "Ordner nicht freigegeben") }
        if mode == .view, let index = currentIndex {
            return String(localized: "\(index + 1) von \(items.count)")
        }
        guard folder != nil || singleFile != nil, !isLoading else { return "" }
        let videos = items.filter(\.isVideo).count
        let images = items.count - videos
        var parts: [String] = []
        if images > 0 || videos == 0 { parts.append(String(localized: "\(images) Bilder")) }
        if videos > 0 { parts.append(String(localized: "\(videos) Videos")) }
        if isReadingCaptureDates { parts.append(String(localized: "Aufnahmedaten werden gelesen …")) }
        return parts.joined(separator: ", ")
    }

    // MARK: Folder

    func showFolder(_ url: URL) {
        guard url.folderURL != folder || singleFile != nil else { return }
        if let folder, !isNavigatingHistory {
            backStack.append(folder)
            forwardStack = []
        }
        setFolder(url.folderURL)
        reload()
    }

    // MARK: History

    /// Folders shown before and, after going back, after the current one – as in a browser.
    private(set) var backStack: [URL] = []
    private(set) var forwardStack: [URL] = []
    @ObservationIgnored private var isNavigatingHistory = false

    var canGoBack: Bool {
        mode == .view || backStack.contains(where: Library.shared.contains)
    }

    var canGoForward: Bool {
        mode == .browse && forwardStack.contains(where: Library.shared.contains)
    }

    /// Back from the single image to the overview, or else to the folder shown before.
    func goBack() {
        if isPresenting { stopPresenting(); return }
        if mode == .view { closeViewer(); return }
        // Folders that are no longer readable, e.g. removed from the sidebar, are skipped.
        while let previous = backStack.popLast() {
            guard Library.shared.contains(previous) else { continue }
            if let folder { forwardStack.append(folder) }
            navigate(to: previous)
            return
        }
    }

    func goForward() {
        guard mode == .browse else { return }
        while let next = forwardStack.popLast() {
            guard Library.shared.contains(next) else { continue }
            if let folder { backStack.append(folder) }
            navigate(to: next)
            return
        }
    }

    private func navigate(to url: URL) {
        isNavigatingHistory = true
        showFolder(url)
        isNavigatingHistory = false
        expandSidebar(toShow: url)
    }

    private func setFolder(_ url: URL?) {
        singleFile = nil
        folder = url
        items = []
        mode = .browse
        selection = []
        cursor = nil
        anchor = nil
        current = nil
        subfolders = []
        allowsLargeScan = false
        confirmsLargeScan = false
    }

    /// Clears the window when its folder is no longer readable, e.g. after it was removed from the sidebar.
    func closeFolderIfUnreadable() {
        guard let folder, !Library.shared.contains(folder) else { return }
        loadTask?.cancel()
        isLoading = false
        setFolder(nil)
    }

    /// Reads the folder again.
    func reload() {
        loadTask?.cancel()
        guard let folder else { return }
        isLoading = true
        subfolderTask?.cancel()
        subfolderTask = Task {
            let found = await Task.detached(priority: .userInitiated) { FolderNode.subfolders(of: folder) }.value
            if !Task.isCancelled && self.folder == folder { subfolders = found }
        }
        confirmsLargeScan = false
        let recursive = includeSubfolders
        let limit = recursive && !allowsLargeScan ? Preferences.subfolderItemLimit : nil
        let scan = Task.detached(priority: .userInitiated) {
            Gallery.scan(folder, recursive: recursive, limit: limit)
        }
        loadTask = Task {
            let found = await withTaskCancellationHandler { await scan.value } onCancel: { scan.cancel() }
            guard !Task.isCancelled else { return }
            if let found {
                apply(found)
            } else {
                isLoading = false
                confirmsLargeScan = true
            }
        }
    }

    /// Answer to the question about a very large folder tree.
    func confirmLargeScan(_ showAll: Bool) {
        confirmsLargeScan = false
        if showAll {
            allowsLargeScan = true
            reload()
        } else {
            includeSubfolders = false
        }
    }

    private func apply(_ found: [MediaItem]) {
        items = sorted(found)
        isLoading = false
        readCaptureDatesIfNeeded()
        let urls = Set(items.map(\.url))
        selection.formIntersection(urls)
        if let cursor, !urls.contains(cursor) { self.cursor = nil }
        if let target = pendingReveal {
            pendingReveal = nil
            let path = target.standardizedFileURL.path
            if let item = items.first(where: { $0.url.standardizedFileURL.path == path }) {
                show(item.url)
                return
            }
        }
        if mode == .view, let current, !urls.contains(current) { closeViewer() }
    }

    /// Images and videos in the folder. nil if there are more than `limit`, or the scan was cancelled.
    nonisolated static func scan(_ folder: URL, recursive: Bool, limit: Int? = nil) -> [MediaItem]? {
        let base = folder.standardizedFileURL.path
        let manager = FileManager.default
        if recursive {
            guard let enumerator = manager.enumerator(at: folder, includingPropertiesForKeys: MediaItem.resourceKeys,
                                                      options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { return [] }
            var found: [MediaItem] = []
            for case let url as URL in enumerator {
                if let item = MediaItem(url: url, base: base) { found.append(item) }
                if let limit, found.count > limit { return nil }
                if found.count % 256 == 0 && Task.isCancelled { return nil }
            }
            return found
        }
        let urls = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: MediaItem.resourceKeys,
                                                     options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { MediaItem(url: $0, base: base) }
    }

    var parentFolder: URL? {
        guard singleFile == nil, let folder else { return nil }
        let parent = folder.deletingLastPathComponent().folderURL
        return parent != folder && Library.shared.contains(parent) ? parent : nil
    }

    /// Back to the overview, or from the overview to the enclosing folder.
    func goUp() {
        if mode == .view {
            closeViewer()
        } else if let parent = parentFolder {
            showFolder(parent)
            expandSidebar(toShow: parent)
        }
    }

    /// Expands the sidebar so that the row of `url` is visible.
    func expandSidebar(toShow url: URL) {
        guard let root = Library.shared.root(containing: url) else { return }
        var folder = root.url
        expanded.insert(folder)
        let relative = url.folderURL.path.dropFirst(root.path.count).split(separator: "/")
        for component in relative.dropLast() {
            folder = folder.appendingPathComponent(String(component), isDirectory: true).folderURL
            expanded.insert(folder)
        }
    }

    // MARK: Files from the Finder

    /// Shows a file opened from the Finder in its folder. If Motiv may not read the folder yet,
    /// it shows the file on its own; the folder can be granted afterwards, see `grantFolderAccess`.
    func reveal(_ file: URL) {
        let library = Library.shared
        if !library.contains(file) {
            showSingleFile(file)
            return
        }
        let parent = file.deletingLastPathComponent().folderURL
        let staysInFolder = singleFile == nil && includeSubfolders && folder?.contains(parent) == true
        if !staysInFolder && parent != folder || singleFile != nil {
            setFolder(parent)
        }
        expandSidebar(toShow: parent)
        pendingReveal = file
        reload()
    }

    /// Asks for the folder of the single file shown, then shows the file among the others.
    func grantFolderAccess() {
        guard let file = singleFile, Library.shared.requestAccess(toFolderOf: file) else { return }
        reveal(file)
    }

    private func showSingleFile(_ file: URL) {
        loadTask?.cancel()
        setFolder(nil)
        singleFile = file
        isLoading = false
        items = MediaItem(url: file, base: file.deletingLastPathComponent().standardizedFileURL.path).map { [$0] } ?? []
        if !items.isEmpty { show(file) }
    }

    // MARK: Selection

    var selectedURLs: [URL] {
        items.map(\.url).filter(selection.contains)
    }

    /// The files commands act on: the image shown, or the selection.
    var targetURLs: [URL] {
        mode == .view ? (current.map { [$0] } ?? []) : selectedURLs
    }

    func index(of url: URL) -> Int? {
        items.firstIndex { $0.url == url }
    }

    func item(for url: URL) -> MediaItem? {
        items.first { $0.url == url }
    }

    var currentIndex: Int? {
        current.flatMap(index(of:))
    }

    func click(_ item: MediaItem, modifiers: NSEvent.ModifierFlags) {
        let url = item.url
        if modifiers.contains(.command) {
            if selection.contains(url) { selection.remove(url) } else { selection.insert(url) }
            anchor = url
        } else if modifiers.contains(.shift), let anchor, let from = index(of: anchor), let to = index(of: url) {
            selection = Set(items[min(from, to)...max(from, to)].map(\.url))
        } else {
            selection = [url]
            anchor = url
        }
        cursor = url
    }

    func selectAll() {
        selection = Set(items.map(\.url))
    }

    /// Selects the first item whose name starts with `text`, or else contains it, as the Finder
    /// does when typing in a folder. Returns whether something matched.
    @discardableResult
    func selectItem(named text: String) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        guard let item = items.first(where: { $0.name.range(of: text, options: options.union(.anchored)) != nil })
                ?? items.first(where: { $0.name.range(of: text, options: options) != nil })
        else { return false }
        selection = [item.url]
        cursor = item.url
        anchor = item.url
        return true
    }

    // MARK: Moving around

    private var activeIndex: Int? {
        (mode == .view ? current : cursor).flatMap(index(of:))
    }

    var hasPrevious: Bool {
        activeIndex.map { $0 > 0 } ?? !items.isEmpty
    }

    var hasNext: Bool {
        activeIndex.map { $0 < items.count - 1 } ?? !items.isEmpty
    }

    /// Moves to another image in the single-image view, or the cursor in the overview.
    func step(_ offset: Int, extendingSelection: Bool = false) {
        guard !items.isEmpty else { return }
        let target = activeIndex.map { $0 + offset } ?? (offset >= 0 ? 0 : items.count - 1)
        go(to: min(max(target, 0), items.count - 1), extendingSelection: extendingSelection)
    }

    func goToFirst(extendingSelection: Bool = false) {
        go(to: 0, extendingSelection: extendingSelection)
    }

    func goToLast(extendingSelection: Bool = false) {
        go(to: items.count - 1, extendingSelection: extendingSelection)
    }

    private func go(to index: Int, extendingSelection: Bool) {
        guard items.indices.contains(index) else { return }
        let url = items[index].url
        if mode == .view {
            show(url)
            return
        }
        cursor = url
        if extendingSelection, let anchor, let from = self.index(of: anchor) {
            selection = Set(items[min(from, index)...max(from, index)].map(\.url))
        } else {
            selection = [url]
            anchor = url
        }
    }

    // MARK: Single-image view

    /// Images open in the single-image view, videos in the app the system uses for them.
    func open(_ item: MediaItem) {
        if item.isVideo {
            FileActions.openWithDefaultApp(item.url)
        } else {
            show(item.url)
        }
    }

    func openCursor() {
        guard let url = cursor ?? selectedURLs.first, let item = item(for: url) else { return }
        open(item)
    }

    func show(_ url: URL) {
        guard let index = index(of: url) else { return }
        current = url
        selection = [url]
        cursor = url
        anchor = url
        mode = .view
        // The next image is the most likely one to be wanted, then the previous one.
        let neighbours = [index + 1, index - 1, index + 2].filter(items.indices.contains).map { items[$0] }
        viewer.show(items[index], preloading: neighbours)
    }

    func closeViewer() {
        if isPresenting { isPresenting = false }
        mode = .browse
    }

    // MARK: Only the image

    /// Shows only the image, full screen. From the overview it starts with the selected image.
    func startPresenting() {
        if mode == .browse {
            guard let url = cursor ?? selectedURLs.first ?? items.first(where: { !$0.isVideo })?.url,
                  let item = item(for: url), !item.isVideo
            else { return }
            show(item.url)
        }
        isPresenting = true
    }

    func stopPresenting() {
        isPresenting = false
    }

    // MARK: Capture dates

    /// Reads the capture dates of the items that lack one, when sorting by capture date.
    private func readCaptureDatesIfNeeded() {
        captureDateTask?.cancel()
        guard sortKey == .captureDate else {
            isReadingCaptureDates = false
            return
        }
        let missing = items.map(\.url).filter { captureDates[$0] == nil }
        guard !missing.isEmpty else { return }
        isReadingCaptureDates = true
        let read = Task.detached(priority: .utility) { () -> [URL: Date] in
            var dates: [URL: Date] = [:]
            for (index, url) in missing.enumerated() {
                if index % 64 == 0 && Task.isCancelled { break }
                // Files without a capture date get their modification date, so they are not read again.
                dates[url] = ImageInfo.captureDate(of: url)
                    ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
            }
            return dates
        }
        captureDateTask = Task {
            let dates = await withTaskCancellationHandler { await read.value } onCancel: { read.cancel() }
            guard !Task.isCancelled else { return }
            captureDates.merge(dates) { $1 }
            isReadingCaptureDates = false
            items = sorted(items)
        }
    }

    // MARK: Zoom

    func zoomIn() {
        if mode == .view {
            viewer.zoomIn()
        } else {
            thumbnailSize = min(thumbnailSize * 1.25, Preferences.thumbnailSizes.upperBound)
        }
    }

    func resetThumbnailSize() {
        thumbnailSize = Preferences.defaultThumbnailSize
    }

    func zoomOut() {
        if mode == .view {
            viewer.zoomOut()
        } else {
            thumbnailSize = max(thumbnailSize / 1.25, Preferences.thumbnailSizes.lowerBound)
        }
    }

    // MARK: Sorting

    private func sorted(_ list: [MediaItem]) -> [MediaItem] {
        let key = sortKey
        let ascending = ascending
        let dates = captureDates
        return list.sorted { a, b in
            let order = Self.compare(a, b, by: key, captureDates: dates)
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }

    /// Items that are equal by the sort key are ordered by path, so the order is always the same.
    private static func compare(_ a: MediaItem, _ b: MediaItem, by key: SortKey, captureDates: [URL: Date]) -> ComparisonResult {
        let order: ComparisonResult = switch key {
        case .name: .orderedSame
        case .captureDate: compare(captureDates[a.url] ?? a.date, captureDates[b.url] ?? b.date)
        case .date: compare(a.date, b.date)
        case .size: compare(a.size, b.size)
        case .kind: (a.type.localizedDescription ?? a.type.identifier)
            .localizedStandardCompare(b.type.localizedDescription ?? b.type.identifier)
        }
        return order == .orderedSame ? a.relativePath.localizedStandardCompare(b.relativePath) : order
    }

    private static func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
    }
}
