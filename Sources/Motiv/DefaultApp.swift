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
import UniformTypeIdentifiers

/// The image formats Motiv offers to open by default. Camera RAW formats are left out on purpose:
/// every camera maker has types of its own, and RAW files usually belong to a photo editor.
enum ImageFormat: String, CaseIterable, Identifiable {
    case jpeg, png, heic, tiff, gif, webp, avif, bmp, icns, ico

    var id: Self { self }

    var title: String {
        switch self {
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .heic: "HEIC / HEIF"
        case .tiff: "TIFF"
        case .gif: "GIF"
        case .webp: "WebP"
        case .avif: "AVIF"
        case .bmp: "BMP"
        case .icns: "ICNS"
        case .ico: "ICO"
        }
    }

    var types: [UTType] {
        switch self {
        case .jpeg: [.jpeg]
        case .png: [.png]
        case .heic: [.heic, .heif]
        case .tiff: [.tiff]
        case .gif: [.gif]
        case .webp: [.webP]
        case .avif: [UTType("public.avif")].compactMap { $0 }
        case .bmp: [.bmp]
        case .icns: [.icns]
        case .ico: [.ico]
        }
    }

    /// The app that opens this format now; for several types, the one for the first.
    var currentApplication: URL? {
        types.first.flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
    }

    var isMotivDefault: Bool {
        types.allSatisfy { type in
            NSWorkspace.shared.urlForApplication(toOpen: type)
                .flatMap { Bundle(url: $0)?.bundleIdentifier } == Bundle.main.bundleIdentifier
        }
    }
}

/// Offers to make Motiv the default app for images – rarely and only once Motiv is really in use:
/// - never before Motiv was used on three different days,
/// - at most twice, the second time 30 days and three more days of use after the first,
/// - never again once Motiv was the default (switching back was a deliberate choice),
/// - only when Motiv is installed in an Applications folder.
@MainActor
enum DefaultAppOffer {
    static let requiredUsageDays = 3
    static let repeatAfter: TimeInterval = 30 * 24 * 60 * 60
    static let maxOffers = 2

    private enum Key {
        static let usageDays = "defaultApp.usageDays"
        static let lastUsageDay = "defaultApp.lastUsageDay"
        static let offerCount = "defaultApp.offerCount"
        static let lastOfferDate = "defaultApp.lastOfferDate"
        static let usageDaysAtLastOffer = "defaultApp.usageDaysAtLastOffer"
        static let wasDefault = "defaultApp.wasDefault"
        /// The app each type had before Motiv, as type identifier → app path, to go back to it.
        static let previousApps = "defaultApp.previousApps"
    }

    private static var defaults: UserDefaults { .standard }
    /// Only one window per app session shows the offer.
    private static var offeredThisSession = false

    // MARK: State of the system

    /// Whether Motiv opens all offered formats.
    static var isDefaultForAll: Bool {
        ImageFormat.allCases.allSatisfy(\.isMotivDefault)
    }

    /// JPEG is the format that matters most; the offer and the summary go by it.
    static var isDefault: Bool {
        ImageFormat.jpeg.isMotivDefault
    }

    /// A copy outside the Applications folders (e.g. a build folder) must not become the default.
    static var isInstalled: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let folders = FileManager.default.urls(for: .applicationDirectory, in: [.localDomainMask, .userDomainMask])
        return folders.contains { path.hasPrefix($0.resolvingSymlinksInPath().path + "/") }
    }

    static var isDefaultForAny: Bool {
        ImageFormat.allCases.contains(where: \.isMotivDefault)
    }

    /// macOS asks the user to confirm each change.
    static func makeDefault(for formats: [ImageFormat] = ImageFormat.allCases) async {
        var previous = previousApps
        for format in formats where !format.isMotivDefault {
            for type in format.types {
                if let app = NSWorkspace.shared.urlForApplication(toOpen: type), !isMotiv(app) {
                    previous[type.identifier] = app.path
                }
                try? await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type)
            }
        }
        defaults.set(previous, forKey: Key.previousApps)
        if formats.contains(where: \.isMotivDefault) { defaults.set(true, forKey: Key.wasDefault) }
    }

    /// Gives the formats back to the app they had before Motiv, or to Preview if that is unknown or
    /// gone. macOS cannot remove a default, only set another one; it asks to confirm each change.
    static func restore(_ formats: [ImageFormat] = ImageFormat.allCases) async {
        var previous = previousApps
        for format in formats where format.isMotivDefault {
            for type in format.types {
                guard let app = restoreApplication(for: type) else { continue }
                try? await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type)
                previous[type.identifier] = nil
            }
        }
        defaults.set(previous, forKey: Key.previousApps)
    }

    /// The app a format goes back to; for several types, the one of the first.
    static func restoreApplication(for format: ImageFormat) -> URL? {
        format.types.first.flatMap(restoreApplication(for:))
    }

    private static func restoreApplication(for type: UTType) -> URL? {
        if let path = previousApps[type.identifier], FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return FileActions.previewApplication
    }

    private static var previousApps: [String: String] {
        defaults.dictionary(forKey: Key.previousApps) as? [String: String] ?? [:]
    }

    private static func isMotiv(_ app: URL) -> Bool {
        Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    // MARK: Usage and offers

    /// Counts the days on which Motiv was used.
    static func recordUsage() {
        let today = Date.now.formatted(.iso8601.year().month().day())
        guard defaults.string(forKey: Key.lastUsageDay) != today else { return }
        defaults.set(today, forKey: Key.lastUsageDay)
        defaults.set(defaults.integer(forKey: Key.usageDays) + 1, forKey: Key.usageDays)
    }

    /// Returns true if the offer should be shown now, and records that it was shown.
    static func claimOffer() -> Bool {
        guard !offeredThisSession, shouldOffer() else { return false }
        offeredThisSession = true
        defaults.set(defaults.integer(forKey: Key.offerCount) + 1, forKey: Key.offerCount)
        defaults.set(Date.now, forKey: Key.lastOfferDate)
        defaults.set(defaults.integer(forKey: Key.usageDays), forKey: Key.usageDaysAtLastOffer)
        return true
    }

    private static func shouldOffer() -> Bool {
        if isDefault {
            defaults.set(true, forKey: Key.wasDefault)
            return false
        }
        guard isInstalled, !defaults.bool(forKey: Key.wasDefault) else { return false }

        let usageDays = defaults.integer(forKey: Key.usageDays)
        switch defaults.integer(forKey: Key.offerCount) {
        case 0:
            return usageDays >= requiredUsageDays
        case ..<maxOffers:
            guard let last = defaults.object(forKey: Key.lastOfferDate) as? Date else { return false }
            let newUsageDays = usageDays - defaults.integer(forKey: Key.usageDaysAtLastOffer)
            return Date.now.timeIntervalSince(last) >= repeatAfter && newUsageDays >= requiredUsageDays
        default:
            return false
        }
    }
}

/// Unobtrusive bar at the top of a window.
struct DefaultAppBanner: View {
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
            Text("Motiv als Standard-App für Bilder verwenden?")
            Spacer(minLength: 8)
            Button("Als Standard festlegen") {
                Task {
                    await DefaultAppOffer.makeDefault()
                    onClose()
                }
            }
            Button("Nicht jetzt", action: onClose)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// Settings row showing the current default app for images, with buttons to change it.
struct DefaultAppSettingsRow: View {
    @State private var summary = Summary.current
    @State private var showsFormats = false

    var body: some View {
        LabeledContent("Standard-App für Bilder") {
            HStack {
                if summary.isAll {
                    Label("Motiv", systemImage: "checkmark")
                } else {
                    Text(summary.text).foregroundStyle(.secondary)
                    Button("Motiv als Standard festlegen") {
                        Task {
                            await DefaultAppOffer.makeDefault()
                            summary = .current
                        }
                    }
                    .disabled(!DefaultAppOffer.isInstalled)
                }
            }
        }
        LabeledContent("Einzelne Bildformate") {
            HStack {
                Button("Zurücksetzen") {
                    Task {
                        await DefaultAppOffer.restore()
                        summary = .current
                    }
                }
                .disabled(!summary.hasMotiv)
                .help("Gibt die Bildformate wieder den Apps, die sie vor Motiv hatten, sonst Vorschau")
                Button("Anpassen …") { showsFormats = true }
                    .disabled(!DefaultAppOffer.isInstalled)
            }
        }
        .sheet(isPresented: $showsFormats, onDismiss: { summary = .current }) {
            DefaultAppFormatsView()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            summary = .current
        }
    }

    private struct Summary {
        var isAll = false
        var hasMotiv = false
        var text: String

        @MainActor static var current: Summary {
            let formats = ImageFormat.allCases
            let motiv = formats.filter(\.isMotivDefault).count
            if motiv == formats.count { return Summary(isAll: true, hasMotiv: true, text: "Motiv") }
            if motiv > 0 {
                return Summary(hasMotiv: true, text: String(localized: "Motiv für \(motiv) von \(formats.count) Formaten"))
            }
            let names = Set(formats.compactMap { $0.currentApplication.map(FileActions.name(of:)) })
            return Summary(text: names.count == 1 ? names.first! : String(localized: "Verschiedene Apps"))
        }
    }
}

/// Sheet listing each image format with the app that opens it.
struct DefaultAppFormatsView: View {
    @Environment(\.dismiss) private var dismiss
    /// Changes when a default was set, so the rows read the system again.
    @State private var generation = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Standard-App nach Bildformat")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(ImageFormat.allCases) { format in
                    GridRow {
                        Text(format.title)
                            .fontWeight(.medium)
                        if let app = format.currentApplication {
                            Label {
                                Text(FileActions.name(of: app))
                            } icon: {
                                Image(nsImage: FileActions.icon(of: app))
                            }
                        } else {
                            Text("Keine").foregroundStyle(.secondary)
                        }
                        if format.isMotivDefault {
                            let target = DefaultAppOffer.restoreApplication(for: format).map(FileActions.name(of:)) ?? String(localized: "Vorschau")
                            Button(String(localized: "Zurück zu \(target)")) {
                                Task {
                                    await DefaultAppOffer.restore([format])
                                    generation += 1
                                }
                            }
                            .controlSize(.small)
                            .gridColumnAlignment(.trailing)
                        } else {
                            Button("Motiv verwenden") {
                                Task {
                                    await DefaultAppOffer.makeDefault(for: [format])
                                    generation += 1
                                }
                            }
                            .controlSize(.small)
                            .gridColumnAlignment(.trailing)
                        }
                    }
                }
            }
            .id(generation)
            Text("macOS fragt bei jeder Änderung einmal nach. Zurücksetzen gibt ein Format der App zurück, die es vor Motiv hatte, sonst Vorschau.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Motiv für alle Formate") {
                    Task {
                        await DefaultAppOffer.makeDefault()
                        generation += 1
                    }
                }
                .disabled(DefaultAppOffer.isDefaultForAll)
                Button("Alle zurücksetzen") {
                    Task {
                        await DefaultAppOffer.restore()
                        generation += 1
                    }
                }
                .disabled(!DefaultAppOffer.isDefaultForAny)
                Spacer()
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .tint(.motivPetrol)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            generation += 1
        }
    }
}
