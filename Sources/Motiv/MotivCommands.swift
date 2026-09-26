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

struct MotivCommands: Commands {
    @FocusedValue(\.gallery) private var gallery
    @Environment(\.openWindow) private var openWindow

    private var targets: [URL] { gallery?.targetURLs ?? [] }
    private var isViewing: Bool { gallery?.mode == .view }
    private var canTransform: Bool { isViewing && gallery?.viewer.canTransform == true }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("Über Motiv") { openWindow(id: "about") }
        }

        CommandGroup(replacing: .help) {
            Button("Hilfe zu Motiv …") { NSWorkspace.shared.open(AppLinks.help) }
                .keyboardShortcut("?")
            Button("Motiv im Web") { NSWorkspace.shared.open(AppLinks.productPage) }
            Divider()
            Button("Motiv auf GitHub") { NSWorkspace.shared.open(AppLinks.sourceCode) }
            Button("Fehler melden oder Idee vorschlagen …") { NSWorkspace.shared.open(AppLinks.reportIssue) }
            Divider()
            Button("Motiv unterstützen …") { openWindow(id: "support") }
        }

        CommandGroup(after: .newItem) {
            Button("Ordner hinzufügen …") {
                if let folder = Library.shared.chooseFolders().first { gallery?.showFolder(folder) }
            }
            .keyboardShortcut("o")
            Divider()
            Button("In Vorschau öffnen") { FileActions.openInPreview(targets) }
                .keyboardShortcut("e")
                .disabled(targets.isEmpty || FileActions.previewApplication == nil)
            OpenWithMenu(urls: targets)
            Button("Im Finder zeigen") { FileActions.revealInFinder(targets.isEmpty ? (gallery?.folder).map { [$0] } ?? [] : targets) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(targets.isEmpty && gallery?.folder == nil)
            Divider()
            Button(favoriteTitle) {
                if let folder = gallery?.folder { Library.shared.toggleFavorite(folder) }
            }
            .keyboardShortcut("t", modifiers: [.command, .control])
            .disabled(gallery?.folder == nil)
        }

        CommandGroup(replacing: .undoRedo) {}

        CommandGroup(replacing: .pasteboard) {
            Button("Kopieren") { FileActions.copy(targets) }
                .keyboardShortcut("c")
                .disabled(targets.isEmpty)
            Button("Alles auswählen") { gallery?.selectAll() }
                .keyboardShortcut("a")
                .disabled(isViewing || gallery?.items.isEmpty != false)
        }

        CommandGroup(after: .toolbar) {
            Divider()
            ForEach(Array(SidebarContent.allCases.enumerated()), id: \.element) { index, content in
                Toggle(content.title, isOn: Binding(
                    get: { gallery?.sidebarContent == content && gallery?.columnVisibility != .detailOnly },
                    set: { _ in gallery?.sidebarContent = content }
                ))
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command, .control])
                .disabled(gallery == nil || gallery?.isPresenting == true)
            }
            Button(infoTitle) { gallery?.toggleInfo() }
                .keyboardShortcut("i")
                .disabled(gallery == nil || gallery?.isPresenting == true)
            Toggle("Sensible Inhalte weichzeichnen", isOn: Binding(
                get: { SensitiveContentGuard.shared.isBlurring },
                set: { SensitiveContentGuard.shared.isPaused = !$0 }
            ))
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(!SensitiveContentGuard.shared.isActive)
            Toggle("Schnellinfo im Bild", isOn: binding(\.showsQuickInfo))
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(gallery == nil)
            Divider()
            Button(gallery?.isPresenting == true ? "Nur Bild beenden" : "Nur Bild im Vollbild") {
                if gallery?.isPresenting == true { gallery?.stopPresenting() } else { gallery?.startPresenting() }
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
            .disabled(gallery?.items.contains { !$0.isVideo } != true)
            Divider()
            Toggle("Unterordner einbeziehen", isOn: binding(\.includeSubfolders))
                .keyboardShortcut("u", modifiers: [.command, .option])
                .disabled(gallery?.folder == nil)
            Menu("Sortieren nach") {
                ForEach(SortKey.allCases) { key in
                    Toggle(key.title, isOn: Binding(
                        get: { gallery?.sortKey == key },
                        set: { _ in gallery?.sortKey = key }
                    ))
                }
                Divider()
                Toggle("Absteigend", isOn: Binding(
                    get: { gallery?.ascending == false },
                    set: { gallery?.ascending = !$0 }
                ))
            }
            .disabled(gallery == nil)
            Toggle("Ordnerleiste", isOn: binding(\.showsFolderStrip))
                .disabled(gallery == nil)
            Toggle("Miniaturleiste", isOn: binding(\.showsFilmstrip))
                .disabled(gallery == nil)
            Divider()
            Button(isViewing ? "Vergrößern" : "Größere Miniaturen") { gallery?.zoomIn() }
                .keyboardShortcut("+")
                .disabled(gallery?.folder == nil && gallery?.singleFile == nil)
            Button(isViewing ? "Verkleinern" : "Kleinere Miniaturen") { gallery?.zoomOut() }
                .keyboardShortcut("-")
                .disabled(gallery?.folder == nil && gallery?.singleFile == nil)
            Button(isViewing ? "Originalgröße" : "Standardgröße der Miniaturen") {
                if isViewing { gallery?.viewer.actualSize() } else { gallery?.resetThumbnailSize() }
            }
            .keyboardShortcut("0")
            .disabled(gallery?.folder == nil && gallery?.singleFile == nil)
            Button("An Fenster anpassen") { gallery?.viewer.fit(.window) }
                .keyboardShortcut("9")
                .disabled(!isViewing)
            Button("An Breite anpassen") { gallery?.viewer.fit(.width) }
                .disabled(!isViewing)
            Button("An Höhe anpassen") { gallery?.viewer.fit(.height) }
                .disabled(!isViewing)
            Button("Zoomstufe eingeben …") { gallery?.viewer.requestsZoomInput = true }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .disabled(!isViewing)
            Divider()
            Button("Aktualisieren") {
                Library.shared.refresh()
                gallery?.reload()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
        }

        CommandMenu("Bild") {
            Button("Nach links drehen") { gallery?.viewer.rotateLeft() }
                .keyboardShortcut("l")
                .disabled(!canTransform)
            Button("Nach rechts drehen") { gallery?.viewer.rotateRight() }
                .keyboardShortcut("r")
                .disabled(!canTransform)
            Divider()
            Button("Horizontal spiegeln") { gallery?.viewer.flipHorizontally() }
                .disabled(!canTransform)
            Button("Vertikal spiegeln") { gallery?.viewer.flipVertically() }
                .disabled(!canTransform)
            Divider()
            Button("Ursprüngliche Ausrichtung") { gallery?.viewer.resetOrientation() }
                .disabled(!canTransform || gallery?.viewer.isTransformed != true)
        }

        CommandMenu("Gehe zu") {
            Button("Zurück") { gallery?.goBack() }
                .keyboardShortcut("[")
                .disabled(!(gallery?.canGoBack ?? false))
            Button("Vorwärts") { gallery?.goForward() }
                .keyboardShortcut("]")
                .disabled(!(gallery?.canGoForward ?? false))
            Divider()
            Button("Vorheriges Bild") { gallery?.step(-1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(!(gallery?.hasPrevious ?? false))
            Button("Nächstes Bild") { gallery?.step(1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(!(gallery?.hasNext ?? false))
            Divider()
            Button("Erstes Bild") { gallery?.goToFirst() }
                .keyboardShortcut(.home, modifiers: .command)
                .disabled(gallery?.items.isEmpty != false)
            Button("Letztes Bild") { gallery?.goToLast() }
                .keyboardShortcut(.end, modifiers: .command)
                .disabled(gallery?.items.isEmpty != false)
            Divider()
            Button(upTitle) { gallery?.goUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(!isViewing && gallery?.parentFolder == nil)
            Button("Öffnen") { gallery?.openCursor() }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(isViewing || gallery?.selection.isEmpty != false)
        }
    }

    private var favoriteTitle: LocalizedStringKey {
        if let folder = gallery?.folder, Library.shared.isFavorite(folder) {
            "Aus Favoriten entfernen"
        } else {
            "Zu Favoriten hinzufügen"
        }
    }

    private var infoTitle: LocalizedStringKey {
        let content = gallery?.sidebarContent
        let visible = gallery?.columnVisibility != .detailOnly
        return visible && (content == .info || content == .both) ? "Informationen ausblenden" : "Informationen einblenden"
    }

    private var upTitle: LocalizedStringKey {
        isViewing ? "Zurück zur Übersicht" : "Übergeordneter Ordner"
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<Gallery, Bool>) -> Binding<Bool> {
        Binding(
            get: { gallery?[keyPath: keyPath] ?? false },
            set: { gallery?[keyPath: keyPath] = $0 }
        )
    }
}
