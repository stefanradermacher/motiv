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

/// One part of a segmented toolbar control: a symbol or a short text, with an action or a menu.
struct ToolbarSegment {
    var symbol: String?
    var title: String?
    /// The widest title the segment will show, e.g. "8888 %". The segment keeps that width,
    /// so the control does not change size while the title changes.
    var widestTitle: String?
    var label: String
    /// Set for a segment that switches something on and off; it then stays pressed while on.
    var isSelected: Bool?
    var isEnabled = true
    var action: (() -> Void)?
    /// Built each time the control updates, so check marks stay current.
    var menu: (() -> NSMenu)?
}

/// A group of toolbar buttons in one capsule with dividers, as in Preview
/// (e.g. zoom out | zoom level | zoom in). SwiftUI's own toolbar groups
/// cannot hold menus in the same capsule, AppKit's segmented control can.
struct ToolbarSegments: NSViewRepresentable {
    let segments: [ToolbarSegment]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.trackingMode = .momentary
        control.segmentStyle = .automatic
        control.target = context.coordinator
        control.action = #selector(Coordinator.clicked(_:))
        // Digits of equal width, so a changing number does not shift.
        control.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: control.controlSize), weight: .regular)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.segments = segments
        control.segmentCount = segments.count
        // Switches stay pressed while on; plain buttons spring back.
        control.trackingMode = segments.contains { $0.isSelected != nil } ? .selectAny : .momentary
        for (index, segment) in segments.enumerated() {
            if let symbol = segment.symbol {
                let image = NSImage(systemSymbolName: symbol, accessibilityDescription: segment.label)
                control.setImage(image, forSegment: index)
                control.setImageScaling(.scaleProportionallyDown, forSegment: index)
            } else {
                control.setImage(nil, forSegment: index)
            }
            control.setLabel(segment.title ?? "", forSegment: index)
            control.setToolTip(segment.label, forSegment: index)
            control.setEnabled(segment.isEnabled, forSegment: index)
            // Plain buttons among switches spring back as well.
            if control.trackingMode == .selectAny { control.setSelected(segment.isSelected ?? false, forSegment: index) }
            let menu = segment.menu?()
            control.setWidth(width(of: segment, hasMenu: menu != nil, in: control), forSegment: index)
            control.setMenu(menu, forSegment: index)
            control.setShowsMenuIndicator(menu != nil, forSegment: index)
        }
        control.setAccessibilityLabel(segments.map(\.label).joined(separator: ", "))
    }

    /// 0 lets the control size the segment itself.
    private func width(of segment: ToolbarSegment, hasMenu: Bool, in control: NSSegmentedControl) -> CGFloat {
        guard let widest = segment.widestTitle else { return 0 }
        let font = control.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let text = (widest as NSString).size(withAttributes: [.font: font]).width
        // Room for the insets of the segment and, if there is one, the menu indicator.
        return ceil(text) + (hasMenu ? 26 : 14)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    final class Coordinator: NSObject {
        var segments: [ToolbarSegment] = []

        @objc func clicked(_ sender: NSSegmentedControl) {
            // With switches, selectedSegment can be -1 after switching one off; the clicked segment
            // is the one whose state no longer matches the model.
            let switched = segments.indices.first { index in
                segments[index].isSelected.map { $0 != sender.isSelected(forSegment: index) } ?? false
            }
            let pressed = segments.indices.first { segments[$0].isSelected == nil && sender.isSelected(forSegment: $0) }
            let index = sender.trackingMode == .selectAny ? (switched ?? pressed ?? sender.selectedSegment) : sender.selectedSegment
            guard segments.indices.contains(index) else { return }
            let segment = segments[index]
            if segment.isSelected == nil, sender.trackingMode == .selectAny {
                sender.setSelected(false, forSegment: index)
            }
            if let action = segment.action {
                action()
            } else if let menu = sender.menu(forSegment: index) {
                // Menu segments open their menu on a simple click.
                let x = (0..<index).reduce(CGFloat(0)) { $0 + sender.width(forSegment: $1) }
                let y = sender.isFlipped ? sender.bounds.height + 4 : -4
                menu.popUp(positioning: nil, at: NSPoint(x: x, y: y), in: sender)
            }
        }
    }
}

/// Menu item that runs a closure.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, symbol: String? = nil, checked: Bool = false, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func run() { handler() }
}
