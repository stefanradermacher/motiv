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
    /// Set up through Screen Time for a child ("Communication Safety"): pictures stay hidden,
    /// neither all of them (pause) nor single ones can be shown.
    private(set) var isStrict: Bool
    /// Blurring paused by the user. Deliberately not stored: the next launch blurs again.
    var isPaused = false

    /// Whether the user may pause blurring or show single pictures.
    var canOverride: Bool {
        isActive && !isStrict
    }

    /// Whether pictures are checked and blurred right now.
    var isBlurring: Bool {
        isActive && !(isPaused && canOverride)
    }

    /// Whether blurring is paused right now.
    var isPausedNow: Bool {
        isPaused && canOverride
    }

    @ObservationIgnored private let analyzer = SCSensitivityAnalyzer()
    @ObservationIgnored private var running: [URL: Task<Bool, Never>] = [:]
    @ObservationIgnored private let limiter = Limiter(limit: 4)

    /// Builds without a developer account lack the entitlement; the policy then reads `.disabled`,
    /// whatever the setting.
    private init() {
        isActive = analyzer.analysisPolicy != .disabled
        isStrict = analyzer.analysisPolicy == .descriptiveInterventions
        // The setting can change while Motiv runs; it is read again whenever Motiv comes to the front.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SensitiveContentGuard.shared.refreshPolicy() }
        }
    }

    func refreshPolicy() {
        let policy = analyzer.analysisPolicy
        let active = policy != .disabled
        if active != isActive { isActive = active }
        let strict = policy == .descriptiveInterventions
        if strict != isStrict { isStrict = strict }
    }

    /// Whether the picture is hidden now; nil while it has not been checked yet.
    func isConcealed(_ url: URL) -> Bool? {
        guard isBlurring, !(canOverride && revealed.contains(url)) else { return false }
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
        guard canOverride else { return }
        revealed.formUnion(urls)
    }

    func conceal(_ urls: [URL]) {
        revealed.subtract(urls)
    }

    /// Videos are judged by their still frame. A failed check counts as not sensitive, as in
    /// Apple's own apps: the warning is a help, not a guarantee.
    private static func analyze(_ url: URL, isVideo: Bool, with analyzer: SCSensitivityAnalyzer) async -> Bool {
        if isVideo {
            guard let frame = await Stills.videoFrame(of: url, pixels: 512) else { return false }
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

    // MARK: Hidden pictures

    /// The colour that replaces a picture for a child, see `isStrict`.
    nonisolated static let strictFill = CGColor(gray: 0.55, alpha: 1)

    /// What the single-image view shows instead of the picture: blurred, or for a child a plain
    /// area, which gives away nothing of the picture at all.
    nonisolated static func concealed(_ image: CGImage, strict: Bool) -> CGImage? {
        strict ? plainArea(like: image) : blurred(image)
    }

    /// A small area of one colour in the proportions of the picture; the canvas scales it up.
    nonisolated private static func plainArea(like image: CGImage) -> CGImage? {
        let scale = 64 / Double(max(image.width, image.height, 1))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.setFillColor(strictFill)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

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

/// Lets only a few tasks run at the same time, so that a large folder does not flood the
/// analysis or the decoding of pictures.
actor Limiter {
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
/// For adults a small panel on the blurred picture, as Apple asks for the Sensitive Content
/// Warning: brief and inline. For a child (Communication Safety) a cover filling the whole view,
/// in simple words, as Apple asks for that setting; the picture cannot be shown there at all.
struct ConcealedOverlay: View {
    let url: URL
    /// Leaves the picture, for the button on the child's cover.
    var onBack: (() -> Void)?

    var body: some View {
        if SensitiveContentGuard.shared.canOverride {
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
        } else {
            ChildSafetyCover(onBack: onBack)
        }
    }
}

/// Covers the whole view for a child. Plain words, no way to see the picture, and no blame.
private struct ChildSafetyCover: View {
    var onBack: (() -> Void)?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.9))
            Text("Dieses Bild wird nicht gezeigt")
                .font(.largeTitle.bold())
            Text("Es könnte etwas zeigen, das dich erschrecken oder verunsichern kann.")
                .font(.title3)
            Text("Du hast nichts falsch gemacht. Wenn du Fragen hast oder dich unwohl fühlst, sprich mit einem Erwachsenen, dem du vertraust.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.85))
            if let onBack {
                Button("Zurück", action: onBack)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, 6)
            }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .frame(maxWidth: 520)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.12, green: 0.30, blue: 0.34))
        .environment(\.colorScheme, .dark)
    }
}

/// Settings row: whether the warning is on, and where to change it.
struct SensitiveContentSettingsRow: View {
    private let guardian = SensitiveContentGuard.shared

    var body: some View {
        LabeledContent {
            Button("Systemeinstellungen …") { SensitiveContentGuard.openSystemSettings() }
        } label: {
            Text("Sensible Inhalte")
            Text(status)
        }
        Toggle("Bis zum Beenden von Motiv nicht weichzeichnen", isOn: Binding(
            get: { guardian.isPausedNow },
            set: { guardian.isPaused = $0 }
        ))
        .disabled(!guardian.canOverride)
    }

    private var status: LocalizedStringKey {
        if !guardian.isActive { return "Nicht geprüft" }
        if guardian.isStrict { return "Weichgezeichnet (Kommunikationssicherheit)" }
        return guardian.isPausedNow ? "Ausgesetzt bis zum Beenden" : "Weichgezeichnet"
    }
}

/// Context menu entries to show hidden pictures or hide them again.
struct SensitiveContentMenu: View {
    let urls: [URL]

    var body: some View {
        let guardian = SensitiveContentGuard.shared
        let concealed = urls.filter { guardian.isConcealed($0) == true }
        let revealed = urls.filter { guardian.revealed.contains($0) && guardian.results[$0] == true }
        if !concealed.isEmpty && guardian.canOverride {
            Divider()
            Button("Sensible Inhalte anzeigen") { guardian.reveal(concealed) }
        } else if !revealed.isEmpty {
            Divider()
            Button("Wieder unscharf zeigen") { guardian.conceal(revealed) }
        }
    }
}
