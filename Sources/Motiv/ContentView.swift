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

/// A window: sidebar with folders, and the overview or the single-image view.
struct ContentView: View {
    @State private var gallery = Gallery()
    @SceneStorage("folder") private var storedFolder = ""
    @Environment(\.openWindow) private var openWindow
    @Environment(\.controlActiveState) private var activeState
    @State private var showsDefaultAppBanner = false
    @State private var window: NSWindow?
    /// How the window looked before showing only the image, to return to it.
    @State private var beforePresenting: (visibility: NavigationSplitViewVisibility, fullScreen: Bool)?

    var body: some View {
        NavigationSplitView(columnVisibility: $gallery.columnVisibility) {
            SidebarView(gallery: gallery)
                .navigationSplitViewColumnWidth(min: 180, ideal: 230, max: 400)
        } detail: {
            detail
                .safeAreaInset(edge: .top, spacing: 0) {
                    if showsDefaultAppBanner {
                        DefaultAppBanner { withAnimation { showsDefaultAppBanner = false } }
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .toolbar { GalleryToolbar(gallery: gallery) }
        }
        .toolbar(gallery.isPresenting ? .hidden : .automatic, for: .windowToolbar)
        .background(WindowReader(window: $window))
        .navigationTitle(gallery.title)
        .navigationSubtitle(gallery.subtitle)
        .focusedSceneValue(\.gallery, gallery)
        // Files from the Finder go to an open window, which OpenRouter picks; without this,
        // SwiftUI would open a new window for each of them.
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .onAppear(perform: start)
        .onDisappear { OpenRouter.shared.remove(gallery) }
        .onChange(of: gallery.folder) { _, folder in
            storedFolder = folder?.path ?? ""
            if let folder { UserDefaults.standard.set(folder.path, forKey: Preferences.lastFolderKey) }
        }
        .onChange(of: activeState) { _, state in
            if state == .key { OpenRouter.shared.activate(gallery) }
        }
        .onChange(of: gallery.isPresenting) { _, presenting in
            if presenting { enterPresentation() } else { leavePresentation() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
            // Leaving full screen by other means, e.g. with the green button, ends it as well.
            if gallery.isPresenting, (note.object as? NSWindow) === window { gallery.stopPresenting() }
        }
    }

    // MARK: Only the image

    private func enterPresentation() {
        let fullScreen = window?.styleMask.contains(.fullScreen) ?? false
        beforePresenting = (gallery.columnVisibility, fullScreen)
        gallery.columnVisibility = .detailOnly
        if !fullScreen { window?.toggleFullScreen(nil) }
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    private func leavePresentation() {
        guard let before = beforePresenting else { return }
        beforePresenting = nil
        gallery.columnVisibility = before.visibility
        if !before.fullScreen, window?.styleMask.contains(.fullScreen) == true { window?.toggleFullScreen(nil) }
    }

    @ViewBuilder private var detail: some View {
        if gallery.folder == nil && gallery.singleFile == nil {
            WelcomeView(gallery: gallery)
        } else if gallery.mode == .view {
            ViewerView(gallery: gallery)
        } else if gallery.showsFolderStrip && (!gallery.subfolders.isEmpty || gallery.parentFolder != nil) {
            FolderStripSplit(gallery: gallery) {
                GridView(gallery: gallery)
            }
        } else {
            GridView(gallery: gallery)
        }
    }

    private func start() {
        OpenRouter.shared.openWindow = { [openWindow] in openWindow(id: "browser") }
        // A restored window knows its own folder; a new one starts with the folder shown last.
        let path = storedFolder.isEmpty ? UserDefaults.standard.string(forKey: Preferences.lastFolderKey) ?? "" : storedFolder
        if !path.isEmpty {
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            if Library.shared.contains(folder) {
                gallery.showFolder(folder)
                gallery.expandSidebar(toShow: folder)
            }
        }
        OpenRouter.shared.takePending(for: gallery)
        DefaultAppOffer.recordUsage()
        if DefaultAppOffer.claimOffer() {
            withAnimation { showsDefaultAppBanner = true }
        }
    }
}

private struct WelcomeView: View {
    let gallery: Gallery

    var body: some View {
        if Library.shared.roots.isEmpty {
            ContentUnavailableView {
                Label("Willkommen bei Motiv", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("Füge einen Ordner mit Bildern hinzu. Motiv merkt sich die Freigabe und zeigt den Ordner künftig in der Seitenleiste.")
            } actions: {
                Button("Ordner hinzufügen …") {
                    if let folder = Library.shared.chooseFolders().first { gallery.showFolder(folder) }
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView("Kein Ordner ausgewählt", systemImage: "folder",
                                   description: Text("Wähle links einen Ordner aus."))
        }
    }
}

/// Hands the window a view lives in to SwiftUI.
private struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { window = view.window }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if view.window !== window { DispatchQueue.main.async { window = view.window } }
    }
}
