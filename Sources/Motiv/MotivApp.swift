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

@main
struct MotivApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Preferences.register()
        TipJar.shared.startListening()
    }

    var body: some Scene {
        WindowGroup(id: "browser") {
            ContentView()
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            SidebarCommands()
            MotivCommands()
        }

        Settings {
            SettingsView()
        }

        Window("Über Motiv", id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
        .commandsRemoved()
        // Files from the Finder belong to a gallery window, never here.
        .handlesExternalEvents(matching: [])

        Window("Motiv unterstützen", id: "support") {
            SupportView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
        .commandsRemoved()
        // Files from the Finder belong to a gallery window, never here.
        .handlesExternalEvents(matching: [])
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mouseMonitor: Any?

    /// The side buttons of a mouse go back and forward, as in a browser. Mouse drivers send them in
    /// different forms: as buttons 4 and 5, or – like SteerMouse's "Back" and "Forward" – as the swipe
    /// of a trackpad or Magic Mouse. Keyboard shortcuts (⌘[ and ⌘]) arrive through the menu.
    func applicationDidFinishLaunching(_ notification: Notification) {
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .swipe]) { event in
            let direction: Int
            switch event.type {
            case .otherMouseDown where event.buttonNumber == 3: direction = -1
            case .otherMouseDown where event.buttonNumber == 4: direction = 1
            // A swipe to the right, like turning a page back.
            case .swipe where event.deltaX > 0: direction = -1
            case .swipe where event.deltaX < 0: direction = 1
            default: return event
            }
            MainActor.assumeIsolated {
                guard let gallery = OpenRouter.shared.activeGallery else { return }
                if direction < 0 { gallery.goBack() } else { gallery.goForward() }
            }
            return nil
        }
    }

    /// Images and folders opened from the Finder or dropped on the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        OpenRouter.shared.open(urls)
    }
}

/// Hands files and folders opened from outside to a window: the one used last,
/// or a new one if none is open.
@MainActor
final class OpenRouter {
    static let shared = OpenRouter()

    private struct WeakGallery {
        weak var gallery: Gallery?
    }

    /// Most recently active last.
    private var galleries: [WeakGallery] = []
    /// Opened while no window was there to take them.
    private var pending: [URL] = []
    /// Opens a new window; set by the first window that appears.
    var openWindow: (() -> Void)?

    /// The window used last.
    var activeGallery: Gallery? {
        galleries.last(where: { $0.gallery != nil })?.gallery
    }

    func activate(_ gallery: Gallery) {
        galleries.removeAll { $0.gallery == nil || $0.gallery === gallery }
        galleries.append(WeakGallery(gallery: gallery))
    }

    func remove(_ gallery: Gallery) {
        galleries.removeAll { $0.gallery == nil || $0.gallery === gallery }
    }

    func open(_ urls: [URL]) {
        if let gallery = galleries.last(where: { $0.gallery != nil })?.gallery {
            handle(urls, in: gallery)
        } else {
            pending += urls
            openWindow?()
        }
    }

    /// Called by a window when it appears.
    func takePending(for gallery: Gallery) {
        activate(gallery)
        guard !pending.isEmpty else { return }
        let urls = pending
        pending = []
        handle(urls, in: gallery)
    }

    private func handle(_ urls: [URL], in gallery: Gallery) {
        // Several files at once all lie in one folder; showing the first one is enough.
        guard let url = urls.first else { return }
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            for folder in urls { Library.shared.add(folder) }
            gallery.showFolder(url.folderURL)
            gallery.expandSidebar(toShow: url.folderURL)
        } else {
            gallery.reveal(url)
        }
    }
}

extension FocusedValues {
    @Entry var gallery: Gallery?
}

extension URL {
    /// The folder in one canonical form, so that the same folder always compares equal.
    var folderURL: URL {
        URL(fileURLWithPath: standardizedFileURL.path, isDirectory: true)
    }

    /// Whether `other` is this folder or lies somewhere inside it.
    func contains(_ other: URL) -> Bool {
        let folder = standardizedFileURL.path
        let path = other.standardizedFileURL.path
        return path == folder || path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }
}
