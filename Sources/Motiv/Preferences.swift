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
    /// After granting access to the folder of a single file: the overview instead of that file.
    static let overviewAfterGrantKey = "overviewAfterGrant"
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
    static let slideshowIntervalKey = "slideshowInterval"
    static let slideshowEndKey = "slideshowEnd"
    static let slideshowTransitionKey = "slideshowTransition"
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
            overviewAfterGrantKey: false,
            includeSubfoldersKey: false,
            sortKeyKey: SortKey.name.rawValue,
            sortAscendingKey: true,
            thumbnailSizeKey: defaultThumbnailSize,
            showsFilmstripKey: true,
            showsQuickInfoKey: false,
            showsFolderStripKey: true,
            folderStripHeightKey: FolderStrip.defaultHeight,
            slideshowIntervalKey: 4,
            slideshowEndKey: SlideshowEnd.loop.rawValue,
            slideshowTransitionKey: SlideTransition.dissolve.rawValue,
        ])
    }

    /// Seconds each image stays in a slideshow.
    static let slideshowIntervals = [2, 3, 4, 5, 8, 10]

    static var slideshowInterval: Int {
        let seconds = UserDefaults.standard.integer(forKey: slideshowIntervalKey)
        return seconds > 0 ? seconds : 4
    }

    static var slideshowTransition: SlideTransition {
        SlideTransition(rawValue: UserDefaults.standard.string(forKey: slideshowTransitionKey) ?? "") ?? .dissolve
    }

    static var slideshowEnd: SlideshowEnd {
        SlideshowEnd(rawValue: UserDefaults.standard.string(forKey: slideshowEndKey) ?? "") ?? .loop
    }

    static var sortKey: SortKey {
        SortKey(rawValue: UserDefaults.standard.string(forKey: sortKeyKey) ?? "") ?? .name
    }
}

/// How a slideshow changes from one image to the next.
enum SlideTransition: String, CaseIterable, Identifiable {
    /// `cut`, not `none`, so that it cannot be mistaken for a missing value.
    case dissolve, push, wipe, clock, iris, cut

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .dissolve: "Überblenden"
        case .push: "Schieben"
        case .wipe: "Wischen"
        case .clock: "Uhrzeiger"
        case .iris: "Kreisblende"
        case .cut: "Ohne Übergang"
        }
    }
}

/// What a slideshow does after the last image.
enum SlideshowEnd: String, CaseIterable, Identifiable {
    case loop, stop, overview

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .loop: "Von vorn beginnen"
        case .stop: "Beim letzten Bild anhalten"
        case .overview: "Zurück zur Übersicht"
        }
    }
}

/// The settings window: tabs in its toolbar, as in other Mac apps, each as tall as its content.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("Allgemein", systemImage: "gearshape") }
            ViewSettings()
                .tabItem { Label("Darstellung", systemImage: "photo") }
            SlideshowSettings()
                .tabItem { Label("Diashow", systemImage: "play.rectangle") }
        }
    }
}

/// A tab of the settings, as wide as all of them and as tall as its content, so that
/// nothing scrolls and no scroller appears.
private struct SettingsTab<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(width: 520)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A short explanation below a setting.
private struct SettingsFooter: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

private struct GeneralSettings: View {
    @AppStorage(Preferences.overviewAfterGrantKey) private var overviewAfterGrant = false

    var body: some View {
        SettingsTab {
            Section {
                DefaultAppSettingsRow()
            } footer: {
                if !DefaultAppOffer.isInstalled {
                    SettingsFooter("Um Motiv als Standard festzulegen, muss die App im Ordner „Programme“ liegen.")
                }
            }
            Section {
                SensitiveContentSettingsRow()
            } footer: {
                SettingsFooter("Ist in den Systemeinstellungen unter „Datenschutz & Sicherheit“ der Hinweis für sensible Inhalte eingeschaltet, zeigt Motiv Bilder mit möglicherweise sensiblen Inhalten zunächst unscharf. Geprüft wird nur auf diesem Mac.")
            }
            Section {
                Toggle("Nach dem Freigeben eines Ordners zur Übersicht wechseln", isOn: $overviewAfterGrant)
            } footer: {
                SettingsFooter("Gilt, wenn du den Ordner eines einzeln geöffneten Bildes freigibst. Sonst bleibt Motiv bei diesem Bild.")
            }
        }
    }
}

private struct ViewSettings: View {
    @AppStorage(Preferences.showNamesKey) private var showNames = true
    @AppStorage(Preferences.usesSystemThumbnailCacheKey) private var usesSystemThumbnailCache = false
    @AppStorage(Preferences.enlargeSmallImagesKey) private var enlargeSmallImages = false

    var body: some View {
        SettingsTab {
            Section {
                Toggle("Dateinamen unter den Miniaturen anzeigen", isOn: $showNames)
                Toggle("Miniaturen im Systemcache ablegen", isOn: $usesSystemThumbnailCache)
            } header: {
                Text("Übersicht")
            } footer: {
                SettingsFooter("Schneller, wenn du einen Ordner wieder öffnest. macOS legt die Miniaturen dann wie für den Finder in seinem geschützten Cache auf der Platte ab. Ausgeschaltet erzeugt Motiv sie soweit möglich selbst und nutzt den Systemcache nur für Formate, die es nicht selbst lesen kann.")
            }
            Section {
                Toggle("Kleine Bilder auf Fenstergröße vergrößern", isOn: $enlargeSmallImages)
            } header: {
                Text("Einzelansicht")
            } footer: {
                SettingsFooter("Gilt beim Öffnen und Blättern. Sonst zeigt Motiv Bilder, die kleiner als das Fenster sind, in Originalgröße; „An Fenster anpassen“ (⌘9) vergrößert sie trotzdem.")
            }
        }
    }
}

private struct SlideshowSettings: View {
    @AppStorage(Preferences.slideshowIntervalKey) private var slideshowInterval = 4
    @AppStorage(Preferences.slideshowEndKey) private var slideshowEnd = SlideshowEnd.loop
    @AppStorage(Preferences.slideshowTransitionKey) private var slideshowTransition = SlideTransition.dissolve

    var body: some View {
        SettingsTab {
            Section {
                Picker("Dauer pro Bild", selection: $slideshowInterval) {
                    ForEach(Preferences.slideshowIntervals, id: \.self) { seconds in
                        Text("\(seconds) Sekunden").tag(seconds)
                    }
                }
                Picker("Übergang", selection: $slideshowTransition) {
                    ForEach(SlideTransition.allCases) { transition in
                        Text(transition.title).tag(transition)
                    }
                }
                Picker("Nach dem letzten Bild", selection: $slideshowEnd) {
                    ForEach(SlideshowEnd.allCases) { end in
                        Text(end.title).tag(end)
                    }
                }
            } footer: {
                SettingsFooter("Die Leertaste startet in der Übersicht eine Diashow mit den ausgewählten Bildern oder, ist nur eines ausgewählt, mit allen Bildern des Ordners. In der Diashow hält die Leertaste an, die Pfeiltasten blättern, Esc führt zurück zur Übersicht.")
            }
        }
    }
}
