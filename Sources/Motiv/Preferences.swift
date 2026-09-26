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

/// User settings, stored in UserDefaults. Sorting, thumbnail size and the like are remembered
/// as last used; the settings window holds only what is rarely changed.
enum Preferences {
    static let showNamesKey = "showNames"
    /// Thumbnails through Quick Look, which keeps them in the system's cache on disk: faster when
    /// a folder is shown again, but copies of the pictures stay behind. Off by default.
    static let usesSystemThumbnailCacheKey = "usesSystemThumbnailCache"
    static let enlargeSmallImagesKey = "enlargeSmallImages"
    static let includeSubfoldersKey = "includeSubfolders"
    static let sortKeyKey = "sortKey"
    static let sortAscendingKey = "sortAscending"
    static let thumbnailSizeKey = "thumbnailSize"
    static let showsFilmstripKey = "showsFilmstrip"
    static let showsQuickInfoKey = "showsQuickInfo"
    static let showsFolderStripKey = "showsFolderStrip"
    static let folderStripHeightKey = "folderStripHeight"
    static let sidebarBrowseKey = "sidebarBrowse"
    static let sidebarViewKey = "sidebarView"
    /// The folder shown last in any window, for new windows.
    static let lastFolderKey = "lastFolder"

    static let thumbnailSizes: ClosedRange<Double> = 64...400
    static let defaultThumbnailSize = 160.0
    /// Above this many images and videos, including subfolders asks first: the grid and the
    /// sorting stay usable, but reading that many files takes a while and a lot of memory.
    static let subfolderItemLimit = 10_000

    static func register() {
        UserDefaults.standard.register(defaults: [
            showNamesKey: true,
            usesSystemThumbnailCacheKey: false,
            enlargeSmallImagesKey: false,
            includeSubfoldersKey: false,
            sortKeyKey: SortKey.name.rawValue,
            sortAscendingKey: true,
            thumbnailSizeKey: defaultThumbnailSize,
            showsFilmstripKey: true,
            showsQuickInfoKey: false,
            showsFolderStripKey: true,
            folderStripHeightKey: FolderStrip.defaultHeight,
        ])
    }

    static var sortKey: SortKey {
        SortKey(rawValue: UserDefaults.standard.string(forKey: sortKeyKey) ?? "") ?? .name
    }
}

struct SettingsView: View {
    @AppStorage(Preferences.showNamesKey) private var showNames = true
    @AppStorage(Preferences.usesSystemThumbnailCacheKey) private var usesSystemThumbnailCache = false
    @AppStorage(Preferences.enlargeSmallImagesKey) private var enlargeSmallImages = false

    var body: some View {
        Form {
            Section {
                DefaultAppSettingsRow()
            } footer: {
                if !DefaultAppOffer.isInstalled {
                    Text("Um Motiv als Standard festzulegen, muss die App im Ordner „Programme“ liegen.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                SensitiveContentSettingsRow()
            } footer: {
                Text("Ist in den Systemeinstellungen unter „Datenschutz & Sicherheit“ der Hinweis für sensible Inhalte eingeschaltet, zeigt Motiv Bilder mit möglicherweise sensiblen Inhalten zunächst unscharf. Geprüft wird nur auf diesem Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Dateinamen unter den Miniaturen anzeigen", isOn: $showNames)
                Toggle("Miniaturen im Systemcache ablegen", isOn: $usesSystemThumbnailCache)
            } header: {
                Text("Übersicht")
            } footer: {
                Text("Schneller, wenn du einen Ordner wieder öffnest. macOS legt die Miniaturen dann wie für den Finder in seinem geschützten Cache auf der Platte ab. Ausgeschaltet erzeugt Motiv sie soweit möglich selbst und nutzt den Systemcache nur für Formate, die es nicht selbst lesen kann.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Kleine Bilder auf Fenstergröße vergrößern", isOn: $enlargeSmallImages)
            } header: {
                Text("Einzelansicht")
            } footer: {
                Text("Gilt beim Öffnen und Blättern. Sonst zeigt Motiv Bilder, die kleiner als das Fenster sind, in Originalgröße; „An Fenster anpassen“ (⌘9) vergrößert sie trotzdem.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}
