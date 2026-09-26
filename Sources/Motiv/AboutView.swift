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

/// Addresses shown in the About window, kept in one place.
enum AppLinks {
    static let sourceCode = URL(string: "https://github.com/stefanradermacher/motiv")!
    static let reportIssue = URL(string: "https://github.com/stefanradermacher/motiv/issues/new")!
    static let moreProjects = URL(string: "https://stefanradermacher.com/projects")!
    static let productPage = URL(string: "https://stefanradermacher.com/projects/motiv")!
    static let help = URL(string: "https://stefanradermacher.com/projects/motiv/support")!
    static let privacy = URL(string: "https://stefanradermacher.com/projects/motiv/datenschutz")!
}

extension Color {
    /// The petrol of the app icon, a little lighter in dark mode.
    static let motivPetrol = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.38, green: 0.70, blue: 0.74, alpha: 1)
            : NSColor(srgbRed: 0.16, green: 0.45, blue: 0.49, alpha: 1)
    })
}

struct AboutView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    private var copyright: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 18) {
            header
            promises
            support
            links
            footer
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .tint(.motivPetrol)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            Text("Motiv")
                .font(.system(size: 26, weight: .semibold))
            Text(version)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Ein schlichter Bild- und Galeriebetrachter für macOS.\nAufgeräumt, schnell und ohne Ablenkung.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            if let nameNote {
                Text(nameNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Only for English readers: what the German app name means.
    private var nameNote: String? {
        guard Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true else { return nil }
        return "“Motiv” [moˈtiːf] is the German word for the subject of a picture."
    }

    /// What Motiv promises: free, open, without ads, without collecting data.
    private var promises: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    promise("Kostenlos", "gift")
                    promise("Open Source (Apache 2.0)", "chevron.left.forwardslash.chevron.right")
                }
                GridRow {
                    promise("Werbefrei", "rectangle.slash")
                    promise("Keine Datensammlung", "hand.raised")
                }
            }
            Text("Motiv hat kein Tracking, keine Analyse und keine Werbung und baut selbst keine Verbindungen ins Internet auf; nur ein freiwilliges Trinkgeld läuft über den App Store. Deine Bilder und Einstellungen bleiben auf deinem Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func promise(_ title: LocalizedStringKey, _ symbol: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 18)
        }
        // Each column is only as wide as its longest entry, so nothing wraps.
        .fixedSize(horizontal: true, vertical: false)
    }

    private var support: some View {
        TipJarView()
    }

    private var links: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                monogram
                Link("Motiv im Web", destination: AppLinks.productPage)
                separator
                Link("Weitere Werkzeuge von mir", destination: AppLinks.moreProjects)
            }
            HStack(spacing: 6) {
                Link("Quellcode auf GitHub", destination: AppLinks.sourceCode)
                separator
                Link("Datenschutz", destination: AppLinks.privacy)
            }
        }
        .font(.callout)
    }

    private var separator: some View {
        Text(verbatim: "·").foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var monogram: some View {
        let name = colorScheme == .dark ? "Monogram-Dark" : "Monogram"
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .frame(width: 18, height: 18)
                .opacity(0.8)
                .accessibilityHidden(true)
        }
    }

    private var footer: some View {
        VStack(spacing: 2) {
            Text("\(copyright) · Apache-Lizenz 2.0")
            Text("Nur Apple-Frameworks, keine Fremdkomponenten.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
}
