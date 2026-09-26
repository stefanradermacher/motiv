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

/// Handing files to other apps. Motiv itself never changes a file; editing, rotating for good
/// or playing videos happens elsewhere.
@MainActor
enum FileActions {
    static var previewApplication: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview")
    }

    static func openInPreview(_ urls: [URL]) {
        guard let preview = previewApplication else { return }
        open(urls, with: preview)
    }

    static func open(_ urls: [URL], with application: URL) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.open(urls, withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration())
    }

    static func openWithDefaultApp(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func revealInFinder(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func copy(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    static func defaultApplication(for url: URL) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: url)
    }

    /// Apps that can open all of the files, the default app first, then by name.
    /// Motiv itself and further copies of the same app are left out.
    static func applications(for urls: [URL]) -> [URL] {
        guard let first = urls.first else { return [] }
        var apps = NSWorkspace.shared.urlsForApplications(toOpen: first)
        for url in urls.dropFirst().prefix(20) {
            let others = Set(NSWorkspace.shared.urlsForApplications(toOpen: url))
            apps = apps.filter(others.contains)
        }
        var seen: Set<String> = [Bundle.main.bundleIdentifier ?? ""]
        apps = apps.filter { app in
            let identifier = Bundle(url: app)?.bundleIdentifier ?? app.path
            return seen.insert(identifier).inserted
        }
        let standard = defaultApplication(for: first)
        return apps.sorted { a, b in
            if isSame(a, standard) != isSame(b, standard) { return isSame(a, standard) }
            return name(of: a).localizedStandardCompare(name(of: b)) == .orderedAscending
        }
    }

    static func isSame(_ app: URL, _ other: URL?) -> Bool {
        other.map { $0.standardizedFileURL.path == app.standardizedFileURL.path } ?? false
    }

    static func name(of application: URL) -> String {
        let name = FileManager.default.displayName(atPath: application.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    static func icon(of application: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: application.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}

/// Submenu listing the apps that can open the files.
struct OpenWithMenu: View {
    let urls: [URL]

    var body: some View {
        Menu("Öffnen mit") {
            let apps = FileActions.applications(for: urls)
            let standard = urls.first.flatMap(FileActions.defaultApplication)
            ForEach(apps, id: \.self) { app in
                Button {
                    FileActions.open(urls, with: app)
                } label: {
                    Label {
                        Text(FileActions.isSame(app, standard)
                             ? String(localized: "\(FileActions.name(of: app)) (Standard)")
                             : FileActions.name(of: app))
                    } icon: {
                        Image(nsImage: FileActions.icon(of: app))
                    }
                }
                if FileActions.isSame(app, standard) && apps.count > 1 {
                    Divider()
                }
            }
        }
        .disabled(urls.isEmpty)
    }
}
