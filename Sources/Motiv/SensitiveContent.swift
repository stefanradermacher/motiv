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
import CoreImage
import Observation
import QuickLookThumbnailing
import Security
import SensitiveContentAnalysis
import SwiftUI

/// Hides pictures that may show nudity until the user chooses to see them, as Messages and AirDrop
/// do. The check runs on the Mac with Apple's model, and only when the user switched on
/// "Sensitive Content Warning" in System Settings; Motiv follows that setting and has none of its own.
@MainActor @Observable
final class SensitiveContentGuard {
    static let shared = SensitiveContentGuard()

    /// Whether the warning is switched on in System Settings.
    private(set) var isActive: Bool
    /// Results so far: true for pictures that may be sensitive.
    private(set) var results: [URL: Bool] = [:]
    /// Pictures the user chose to see, until Motiv quits.
    private(set) var revealed: Set<URL> = []
    /// Blurring paused by the user. Deliberately not stored: the next launch blurs again.
    var isPaused = false

    /// Whether pictures are checked and blurred right now.
    var isBlurring: Bool {
        isActive && !isPaused
    }

    @ObservationIgnored private let analyzer = SCSensitivityAnalyzer()
    @ObservationIgnored private var running: [URL: Task<Bool, Never>] = [:]
    @ObservationIgnored private let limiter = Limiter(limit: 4)

    /// Builds without a developer account lack the entitlement; they never check, whatever the setting.
    @ObservationIgnored private let isEntitled: Bool = {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "com.apple.developer.sensitivecontentanalysis.client" as CFString, nil) != nil
    }()

    private init() {
        isActive = isEntitled && analyzer.analysisPolicy != .disabled
        // The setting can change while Motiv runs; it is read again whenever Motiv comes to the front.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SensitiveContentGuard.shared.refreshPolicy() }
        }
    }

    func refreshPolicy() {
        let active = isEntitled && analyzer.analysisPolicy != .disabled
        if active != isActive { isActive = active }
    }

    /// Whether the picture is hidden now; nil while it has not been checked yet.
    func isConcealed(_ url: URL) -> Bool? {
        guard isBlurring, !revealed.contains(url) else { return false }
        return results[url]
    }

    /// Checks a picture once; later calls return the stored result.
    @discardableResult
    func check(_ url: URL, isVideo: Bool) async -> Bool {
        guard isBlurring else { return false }
        if let result = results[url] { return result }
        let task = running[url] ?? Task {
            await limiter.acquire()
            defer { Task { await limiter.release() } }
            return await Self.analyze(url, isVideo: isVideo, with: analyzer)
        }
        running[url] = task
        let result = await task.value
        running[url] = nil
        results[url] = result
        return result
    }

    func reveal(_ urls: [URL]) {
        revealed.formUnion(urls)
    }

    func conceal(_ urls: [URL]) {
        revealed.subtract(urls)
    }

    /// Videos are judged by their still frame. A failed check counts as not sensitive, as in
    /// Apple's own apps: the warning is a help, not a guarantee.
    private static func analyze(_ url: URL, isVideo: Bool, with analyzer: SCSensitivityAnalyzer) async -> Bool {
        if isVideo {
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 512, height: 512),
                                                       scale: 1, representationTypes: .thumbnail)
            guard let frame = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage
            else { return false }
            return (try? await analyzer.analyzeImage(frame))?.isSensitive ?? false
        }
        return (try? await analyzer.analyzeImage(at: url))?.isSensitive ?? false
    }

    /// Opens Privacy & Security in System Settings, where the warning is switched on and off.
    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Blurred pictures

    /// A strongly blurred, small copy of a picture for the single-image view.
    nonisolated static func blurred(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        // Scaled down first: blurring a large photo at full size would take long for no gain.
        let scale = min(1, 256 / max(input.extent.width, input.extent.height))
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let blurred = small.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 14])
            .cropped(to: small.extent)
        return CIContext().createCGImage(blurred, from: small.extent)
    }
}

/// Lets only a few checks run at the same time, so a large folder does not flood the analysis.
private actor Limiter {
    private let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        if waiting.isEmpty {
            running -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}

/// Covers a hidden thumbnail: the blurred picture with a crossed-out eye.
struct ConcealedBadge: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "eye.slash.fill")
            .font(.system(size: max(10, min(size * 0.18, 28))))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 2)
            .accessibilityLabel(Text("Möglicherweise sensibler Inhalt"))
    }
}

/// On top of a hidden picture in the single-image view.
struct ConcealedOverlay: View {
    let url: URL

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "eye.slash")
                .font(.system(size: 44, weight: .light))
            Text("Dieses Bild enthält möglicherweise sensible Inhalte.")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Der Hinweis für sensible Inhalte ist in den Systemeinstellungen eingeschaltet.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Anzeigen") { SensitiveContentGuard.shared.reveal([url]) }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Settings row: whether the warning is on, and where to change it.
struct SensitiveContentSettingsRow: View {
    private let guardian = SensitiveContentGuard.shared

    var body: some View {
        LabeledContent("Sensible Inhalte") {
            HStack {
                Text(guardian.isActive ? "Weichgezeichnet" : "Nicht geprüft")
                    .foregroundStyle(.secondary)
                Button("Systemeinstellungen …") { SensitiveContentGuard.openSystemSettings() }
            }
        }
        Toggle("Bis zum Beenden von Motiv nicht weichzeichnen", isOn: Binding(
            get: { guardian.isPaused },
            set: { guardian.isPaused = $0 }
        ))
        .disabled(!guardian.isActive)
    }
}

/// Context menu entries to show hidden pictures or hide them again.
struct SensitiveContentMenu: View {
    let urls: [URL]

    var body: some View {
        let guardian = SensitiveContentGuard.shared
        let concealed = urls.filter { guardian.isConcealed($0) == true }
        let revealed = urls.filter { guardian.revealed.contains($0) && guardian.results[$0] == true }
        if !concealed.isEmpty {
            Divider()
            Button("Sensible Inhalte anzeigen") { guardian.reveal(concealed) }
        } else if !revealed.isEmpty {
            Divider()
            Button("Wieder unscharf zeigen") { guardian.conceal(revealed) }
        }
    }
}
