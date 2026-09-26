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

import AVFoundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

struct InfoEntry: Identifiable, Hashable, Sendable {
    let label: String
    let value: String
    var id: String { label }
}

struct InfoSection: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case file, image, capture, location, description, video
    }

    let kind: Kind
    let entries: [InfoEntry]
    var id: Kind { kind }

    var title: String {
        switch kind {
        case .file: String(localized: "Datei")
        case .image: String(localized: "Bild")
        case .capture: String(localized: "Aufnahme")
        case .location: String(localized: "Ort")
        case .description: String(localized: "Beschreibung")
        case .video: String(localized: "Video")
        }
    }
}

/// What Motiv knows about one image or video: file facts, image properties, EXIF, IPTC, GPS.
/// Only the metadata is read, never the whole image, so this takes milliseconds.
struct ImageInfo: Sendable {
    var sections: [InfoSection] = []
    /// Every metadata field the file carries, grouped as ImageIO names them.
    var allMetadata: [InfoEntry] = []
    var latitude: Double?
    var longitude: Double?
    /// One line for the quick info bar, e.g. "4000 × 3000 · 2,4 MB · f/2,8 · 1/250 s · ISO 200".
    var summary = ""
    var captureDate: Date?

    var mapsURL: URL? {
        guard let latitude, let longitude else { return nil }
        // Opens the Maps app; Motiv itself connects to nothing.
        return URL(string: "maps://?ll=\(latitude),\(longitude)&q=\(latitude),\(longitude)")
    }

    // MARK: Loading

    nonisolated static func load(_ item: MediaItem) async -> ImageInfo {
        var info = ImageInfo()
        var summary: [String] = []
        let file = fileEntries(item)
        if item.isVideo {
            let video = await videoEntries(item.url)
            info.sections.append(InfoSection(kind: .file, entries: file))
            if !video.entries.isEmpty { info.sections.append(InfoSection(kind: .video, entries: video.entries)) }
            info.captureDate = video.date
            summary = video.summary
            summary.append(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))
        } else {
            let image = await Task.detached(priority: .userInitiated) { imageMetadata(item.url) }.value
            info.sections.append(InfoSection(kind: .file, entries: file))
            for section in image.sections where !section.entries.isEmpty { info.sections.append(section) }
            info.allMetadata = image.all
            info.latitude = image.latitude
            info.longitude = image.longitude
            info.captureDate = image.captureDate
            summary = image.summary
            summary.insert(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file),
                           at: min(1, summary.count))
        }
        info.summary = summary.joined(separator: " · ")
        return info
    }

    /// The capture date alone, for sorting; nil if the file does not record one.
    nonisolated static func captureDate(of url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        return captureDate(in: properties)
    }

    private nonisolated static func captureDate(in properties: [CFString: Any]) -> Date? {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String
            ?? exif[kCGImagePropertyExifDateTimeDigitized] as? String
            ?? tiff[kCGImagePropertyTIFFDateTime] as? String
        return text.flatMap(exifDateFormatter.date(from:))
    }

    private nonisolated static let exifDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter
    }()

    // MARK: File

    private nonisolated static func fileEntries(_ item: MediaItem) -> [InfoEntry] {
        let url = item.url
        var entries = [
            InfoEntry(label: String(localized: "Name"), value: url.lastPathComponent),
            InfoEntry(label: String(localized: "Ort"), value: (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath),
            InfoEntry(label: String(localized: "Art"), value: item.type.localizedDescription ?? item.type.identifier),
            InfoEntry(label: String(localized: "Größe"), value: String(localized: "\(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file)) (\(item.size.formatted()) Bytes)")),
        ]
        if let values = try? url.resourceValues(forKeys: [.creationDateKey]), let created = values.creationDate {
            entries.append(InfoEntry(label: String(localized: "Erstellt"), value: format(created)))
        }
        entries.append(InfoEntry(label: String(localized: "Geändert"), value: format(item.date)))
        return entries
    }

    private nonisolated static func format(_ date: Date) -> String {
        date.formatted(date: .long, time: .shortened)
    }

    // MARK: Image

    private struct ImageMetadata: Sendable {
        var sections: [InfoSection] = []
        var all: [InfoEntry] = []
        var latitude: Double?
        var longitude: Double?
        var captureDate: Date?
        var summary: [String] = []
    }

    private nonisolated static func imageMetadata(_ url: URL) -> ImageMetadata {
        var result = ImageMetadata()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, source.largestImageIndex, nil) as? [CFString: Any]
        else { return result }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let exifAux = properties[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]

        // Image
        var image: [InfoEntry] = []
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        if var width = properties[kCGImagePropertyPixelWidth] as? Int, var height = properties[kCGImagePropertyPixelHeight] as? Int {
            // As shown: sideways orientations swap the stored dimensions.
            if (5...8).contains(orientation) { swap(&width, &height) }
            let megapixels = (Double(width * height) / 1_000_000).formatted(.number.precision(.fractionLength(1)))
            image.append(InfoEntry(label: String(localized: "Maße"), value: String(localized: "\(width) × \(height) Pixel (\(megapixels) MP)")))
            result.summary.append("\(width) × \(height)")
        }
        let frames = CGImageSourceGetCount(source)
        let sizes = source.imageSizes
        if !sizes.isEmpty {
            // Icons: one picture in several sizes.
            image.append(InfoEntry(label: String(localized: "Enthaltene Größen"),
                                   value: String(localized: "\(sizes.map(String.init).joined(separator: ", ")) Pixel")))
        } else if frames > 1 {
            image.append(InfoEntry(label: String(localized: "Einzelbilder"), value: "\(frames)"))
        }
        if let profile = properties[kCGImagePropertyProfileName] as? String {
            image.append(InfoEntry(label: String(localized: "Farbprofil"), value: profile))
        } else if let model = properties[kCGImagePropertyColorModel] as? String {
            image.append(InfoEntry(label: String(localized: "Farbmodell"), value: model))
        }
        if let depth = properties[kCGImagePropertyDepth] as? Int {
            image.append(InfoEntry(label: String(localized: "Farbtiefe"), value: String(localized: "\(depth) Bit pro Kanal")))
        }
        if let dpi = properties[kCGImagePropertyDPIWidth] as? Double {
            image.append(InfoEntry(label: String(localized: "Auflösung"), value: "\(Int(dpi.rounded())) dpi"))
        }
        if orientation != 1 {
            image.append(InfoEntry(label: String(localized: "Ausrichtung"), value: orientationText(orientation)))
        }
        if let alpha = properties[kCGImagePropertyHasAlpha] as? Bool, alpha {
            image.append(InfoEntry(label: String(localized: "Transparenz"), value: String(localized: "Ja")))
        }
        result.sections.append(InfoSection(kind: .image, entries: image))

        // Capture
        var capture: [InfoEntry] = []
        result.captureDate = captureDate(in: properties)
        if let date = result.captureDate {
            capture.append(InfoEntry(label: String(localized: "Aufgenommen"), value: format(date)))
        }
        let make = (tiff[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(in: .whitespaces)
        let model = (tiff[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespaces)
        if let camera = cameraName(make: make, model: model) {
            capture.append(InfoEntry(label: String(localized: "Kamera"), value: camera))
        }
        if let lens = exif[kCGImagePropertyExifLensModel] as? String ?? exifAux[kCGImagePropertyExifAuxLensModel] as? String {
            capture.append(InfoEntry(label: String(localized: "Objektiv"), value: lens))
        }
        if let focal = exif[kCGImagePropertyExifFocalLength] as? Double {
            var text = "\(focal.formatted(.number.precision(.fractionLength(0...1)))) mm"
            if let equivalent = exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Int, abs(Double(equivalent) - focal) >= 1 {
                text += String(localized: " (\(equivalent) mm Kleinbild)")
            }
            capture.append(InfoEntry(label: String(localized: "Brennweite"), value: text))
        }
        if let number = exif[kCGImagePropertyExifFNumber] as? Double {
            let text = "f/\(number.formatted(.number.precision(.fractionLength(0...1))))"
            capture.append(InfoEntry(label: String(localized: "Blende"), value: text))
            result.summary.append(text)
        }
        if let time = exif[kCGImagePropertyExifExposureTime] as? Double, time > 0 {
            let text = time < 1 ? "1/\(Int((1 / time).rounded())) s" : "\(time.formatted(.number.precision(.fractionLength(0...1)))) s"
            capture.append(InfoEntry(label: String(localized: "Belichtungszeit"), value: text))
            result.summary.append(text)
        }
        if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first {
            capture.append(InfoEntry(label: "ISO", value: "\(iso)"))
            result.summary.append("ISO \(iso)")
        }
        if let bias = exif[kCGImagePropertyExifExposureBiasValue] as? Double, bias != 0 {
            let text = (bias > 0 ? "+" : "") + bias.formatted(.number.precision(.fractionLength(0...1))) + " EV"
            capture.append(InfoEntry(label: String(localized: "Belichtungskorrektur"), value: text))
        }
        if let flash = exif[kCGImagePropertyExifFlash] as? Int {
            capture.append(InfoEntry(label: String(localized: "Blitz"),
                                     value: flash & 1 == 1 ? String(localized: "Ausgelöst") : String(localized: "Nicht ausgelöst")))
        }
        if let balance = exif[kCGImagePropertyExifWhiteBalance] as? Int {
            capture.append(InfoEntry(label: String(localized: "Weißabgleich"),
                                     value: balance == 0 ? String(localized: "Automatisch") : String(localized: "Manuell")))
        }
        if let software = tiff[kCGImagePropertyTIFFSoftware] as? String {
            capture.append(InfoEntry(label: String(localized: "Software"), value: software))
        }
        if let focal = exif[kCGImagePropertyExifFocalLength] as? Double {
            result.summary.append("\(focal.formatted(.number.precision(.fractionLength(0)))) mm")
        }
        result.sections.append(InfoSection(kind: .capture, entries: capture))

        // Location
        var location: [InfoEntry] = []
        if let latitude = gps[kCGImagePropertyGPSLatitude] as? Double, let longitude = gps[kCGImagePropertyGPSLongitude] as? Double {
            let north = (gps[kCGImagePropertyGPSLatitudeRef] as? String) != "S"
            let east = (gps[kCGImagePropertyGPSLongitudeRef] as? String) != "W"
            result.latitude = north ? latitude : -latitude
            result.longitude = east ? longitude : -longitude
            let digits = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(5))
            let latitudeText = "\(latitude.formatted(digits))° \(north ? String(localized: "N") : String(localized: "S"))"
            let longitudeText = "\(longitude.formatted(digits))° \(east ? String(localized: "O") : String(localized: "W"))"
            location.append(InfoEntry(label: String(localized: "Koordinaten"), value: "\(latitudeText), \(longitudeText)"))
            if let altitude = gps[kCGImagePropertyGPSAltitude] as? Double {
                let below = (gps[kCGImagePropertyGPSAltitudeRef] as? Int) == 1
                location.append(InfoEntry(label: String(localized: "Höhe"), value: "\(below ? "-" : "")\(Int(altitude.rounded())) m"))
            }
        }
        result.sections.append(InfoSection(kind: .location, entries: location))

        // Description
        var description: [InfoEntry] = []
        func add(_ label: String, _ value: Any?) {
            let text: String? = if let list = value as? [String] { list.joined(separator: ", ") } else { value as? String }
            if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                description.append(InfoEntry(label: label, value: text))
            }
        }
        add(String(localized: "Titel"), iptc[kCGImagePropertyIPTCObjectName])
        add(String(localized: "Beschreibung"), iptc[kCGImagePropertyIPTCCaptionAbstract] ?? tiff[kCGImagePropertyTIFFImageDescription])
        add(String(localized: "Schlagwörter"), iptc[kCGImagePropertyIPTCKeywords])
        add(String(localized: "Urheber"), iptc[kCGImagePropertyIPTCByline] ?? tiff[kCGImagePropertyTIFFArtist])
        add(String(localized: "Copyright"), iptc[kCGImagePropertyIPTCCopyrightNotice] ?? tiff[kCGImagePropertyTIFFCopyright])
        result.sections.append(InfoSection(kind: .description, entries: description))

        result.all = flatten(properties)
        return result
    }

    private nonisolated static func cameraName(make: String?, model: String?) -> String? {
        switch (make, model) {
        case let (make?, model?):
            // Many cameras repeat the maker in the model name, e.g. "Canon" + "Canon EOS R6".
            model.lowercased().hasPrefix(make.lowercased().split(separator: " ").first.map(String.init) ?? make.lowercased())
                ? model : "\(make) \(model)"
        case let (make?, nil): make
        case let (nil, model?): model
        default: nil
        }
    }

    private nonisolated static func orientationText(_ value: Int) -> String {
        switch value {
        case 2: String(localized: "Horizontal gespiegelt")
        case 3: String(localized: "Um 180° gedreht")
        case 4: String(localized: "Vertikal gespiegelt")
        case 6: String(localized: "90° im Uhrzeigersinn")
        case 8: String(localized: "90° gegen den Uhrzeigersinn")
        case 5, 7: String(localized: "Gespiegelt und um 90° gedreht")
        default: String(localized: "Normal")
        }
    }

    /// All properties as "Group › Key" and value, e.g. "Exif › FNumber: 2.8".
    private nonisolated static func flatten(_ properties: [CFString: Any]) -> [InfoEntry] {
        var entries: [InfoEntry] = []
        func visit(_ dictionary: [String: Any], group: String?) {
            for (key, value) in dictionary {
                let name = key.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
                if let nested = value as? [String: Any] {
                    visit(nested, group: group.map { "\($0) › \(name)" } ?? name)
                } else {
                    entries.append(InfoEntry(label: group.map { "\($0) › \(name)" } ?? name, value: describe(value)))
                }
            }
        }
        visit(properties as [String: Any], group: nil)
        return entries.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    private nonisolated static func describe(_ value: Any) -> String {
        switch value {
        case let list as [Any]: list.map(describe).joined(separator: ", ")
        case let data as Data: String(localized: "\(data.count) Bytes")
        case let number as NSNumber: number.stringValue
        default: "\(value)"
        }
    }

    // MARK: Video

    private nonisolated static func videoEntries(_ url: URL) async -> (entries: [InfoEntry], summary: [String], date: Date?) {
        let asset = AVURLAsset(url: url)
        var entries: [InfoEntry] = []
        var summary: [String] = []
        var date: Date?
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let (size, transform, rate, formats) = try? await track.load(.naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions) {
            let shown = size.applying(transform)
            let width = Int(abs(shown.width).rounded())
            let height = Int(abs(shown.height).rounded())
            entries.append(InfoEntry(label: String(localized: "Maße"), value: String(localized: "\(width) × \(height) Pixel")))
            summary.append("\(width) × \(height)")
            if rate > 0 {
                entries.append(InfoEntry(label: String(localized: "Bildrate"),
                                         value: String(localized: "\(Double(rate).formatted(.number.precision(.fractionLength(0...2)))) Bilder/s")))
            }
            if let format = formats.first {
                entries.append(InfoEntry(label: String(localized: "Codec"), value: fourCC(CMFormatDescriptionGetMediaSubType(format))))
            }
        }
        if let duration = try? await asset.load(.duration), duration.seconds.isFinite {
            let text = Duration.seconds(duration.seconds).formatted(.time(pattern: duration.seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
            entries.insert(InfoEntry(label: String(localized: "Dauer"), value: text), at: 0)
            summary.insert(text, at: 0)
        }
        if let item = try? await asset.load(.creationDate), let value = try? await item.load(.dateValue) {
            date = value
            entries.append(InfoEntry(label: String(localized: "Aufgenommen"), value: format(value)))
        }
        return (entries, summary, date)
    }

    private nonisolated static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xff) }
        let text = String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
        switch text {
        case "avc1": return "H.264"
        case "hvc1", "hev1": return "HEVC (H.265)"
        case "ap4h", "apch", "apcn", "apcs", "apco": return "Apple ProRes"
        default: return text
        }
    }
}

extension CGImageSource {
    /// The index of the largest image. Icon files (ICNS, ICO) hold one icon in several sizes, not
    /// necessarily the largest first; for other files this is usually the first image.
    nonisolated var largestImageIndex: Int {
        (0..<CGImageSourceGetCount(self)).max { area(at: $0) < area(at: $1) } ?? 0
    }

    /// The distinct pixel widths of the images, if the file holds several sizes of one picture.
    nonisolated var imageSizes: [Int] {
        let widths = (0..<CGImageSourceGetCount(self)).compactMap { index in
            (CGImageSourceCopyPropertiesAtIndex(self, index, nil) as? [CFString: Any])?[kCGImagePropertyPixelWidth] as? Int
        }
        let distinct = Set(widths)
        return distinct.count > 1 ? distinct.sorted() : []
    }

    private nonisolated func area(at index: Int) -> Int {
        let properties = CGImageSourceCopyPropertiesAtIndex(self, index, nil) as? [CFString: Any] ?? [:]
        return (properties[kCGImagePropertyPixelWidth] as? Int ?? 0) * (properties[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }
}

/// Keeps the information of recently shown files, so the sidebar and the quick info bar share
/// one reading and stepping back is instant.
@MainActor
final class ImageInfoCache {
    static let shared = ImageInfoCache()

    private var entries: [URL: ImageInfo] = [:]
    private var order: [URL] = []
    private var loading: [URL: Task<ImageInfo, Never>] = [:]
    private let limit = 200

    func info(for item: MediaItem) async -> ImageInfo {
        if let info = entries[item.url] { return info }
        let task = loading[item.url] ?? Task { await ImageInfo.load(item) }
        loading[item.url] = task
        let info = await task.value
        loading[item.url] = nil
        entries[item.url] = info
        order.append(item.url)
        if order.count > limit { entries.removeValue(forKey: order.removeFirst()) }
        return info
    }

    func cached(_ url: URL) -> ImageInfo? {
        entries[url]
    }
}
