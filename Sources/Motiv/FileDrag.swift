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
import UniformTypeIdentifiers

/// Dragging image files out of Motiv, to the Finder or into other apps. Motiv itself only reads:
/// the app that receives the files copies them, or, like the Finder on the same disk, moves them.
@MainActor
enum FileDrag {
    /// The source of the drag under way, kept until it ends.
    private static var source: Source?

    /// Starts a drag with `urls` from the mouse event being handled, which must be a drag of the
    /// left mouse button. `onMove` runs if the receiver moved the files away.
    @discardableResult
    static func begin(_ urls: [URL], onMove: @escaping () -> Void) -> Bool {
        guard source == nil, !urls.isEmpty,
              let event = NSApp.currentEvent, event.type == .leftMouseDragged,
              let view = event.window?.contentView
        else { return false }
        let point = view.convert(event.locationInWindow, from: nil)
        let items = urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let image = ThumbnailCache.shared.cached(url, pixels: 256) ?? NSWorkspace.shared.icon(forFile: url.path)
            let side: CGFloat = 96
            let size = image.size.width >= image.size.height
                ? NSSize(width: side, height: side * image.size.height / max(image.size.width, 1))
                : NSSize(width: side * image.size.width / max(image.size.height, 1), height: side)
            let offset = CGFloat(min(index, 4)) * 4
            item.setDraggingFrame(NSRect(x: point.x - size.width / 2 + offset, y: point.y - size.height / 2 - offset,
                                         width: size.width, height: size.height), contents: image)
            return item
        }
        let source = Source(onMove: onMove)
        self.source = source
        let session = view.beginDraggingSession(with: items, event: event, source: source)
        session.draggingFormation = .pile
        session.animatesToStartingPositionsOnCancelOrFail = true
        return true
    }

    private final class Source: NSObject, NSDraggingSource {
        let onMove: () -> Void

        init(onMove: @escaping () -> Void) {
            self.onMove = onMove
        }

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            // Inside Motiv a drop means nothing; elsewhere the receiver chooses.
            context == .outsideApplication ? [.copy, .move, .generic] : []
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            MainActor.assumeIsolated {
                if operation.contains(.move) { onMove() }
                FileDrag.source = nil
            }
        }
    }
}

/// Image data for the pasteboard, made only when an app asks for it: the file's own format, and
/// TIFF for apps that take nothing else.
final class ImageDataProvider: NSObject, NSPasteboardItemDataProvider {
    /// The provider of the image copied last; the pasteboard item does not keep it alive.
    @MainActor static var current: ImageDataProvider?

    let url: URL

    init(url: URL) {
        self.url = url
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        if type == .tiff {
            if let image = NSImage(contentsOf: url), let data = image.tiffRepresentation { item.setData(data, forType: type) }
        } else if let data = try? Data(contentsOf: url) {
            item.setData(data, forType: type)
        }
    }
}
