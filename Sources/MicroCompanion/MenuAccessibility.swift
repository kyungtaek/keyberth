import AppKit
import SwiftUI

/// A status item is hosted by the system menu bar on recent macOS. Some
/// accessibility clients enumerate only ordinary app windows. Give those
/// clients a reference to the real status button and its native action.
@MainActor final class StatusMenu: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()

    init(model: Companion) {
        super.init()
        popover.contentViewController = NSHostingController(rootView: SlotPanel(model: model))
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        guard let button = item.button else { return }
        button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: DeckBrand.name)
        button.toolTip = DeckBrand.name + " · cmux"
        button.setAccessibilityLabel(DeckBrand.name + " 메뉴 막대 아이콘")
        button.target = self
        button.action = #selector(toggle)
        button.setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "슬롯 팝오버 열기") { [weak button] in
            guard let button else { return false }
            button.performClick(nil)
            return true
        }])
    }

    func linkButton(to window: NSWindow) {
        guard let button = item.button else { return }
        window.setAccessibilityChildren((window.accessibilityChildren() ?? []) + [button])
    }

    @objc private func toggle() {
        if popover.isShown { popover.performClose(nil) }
        else { open() }
    }
    func close() { popover.performClose(nil) }
    func open() {
        guard let button = item.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let window = popover.contentViewController?.view.window {
            window.title = DeckBrand.name + " 슬롯 팝오버"
            window.setAccessibilityLabel(window.title)
            window.setAccessibilityIdentifier("micro-status-popover")
            window.makeKey()
        }
    }
}
