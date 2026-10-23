import AppKit
import SwiftUI

/// The roulette's own window, built on first use and brought forward after that. Every opening reloads the
/// table unless a spin is on it.
final class RouletteWindow {
    private let makeModel: () throws -> RouletteModel
    private var model: RouletteModel?
    private var window: NSWindow?
    private var spaceBar: Any?

    private static let spaceKeyCode: UInt16 = 49

    init(makeModel: @escaping () throws -> RouletteModel) {
        self.makeModel = makeModel
    }

    func show() {
        do {
            let model = try self.model ?? makeModel()
            self.model = model
            let window = window ?? makeWindow(for: model)
            self.window = window
            model.reload()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } catch {
            Log.write("roulette could not open: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "No pude abrir la ruleta"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private func makeWindow(for model: RouletteModel) -> NSWindow {
        let host = NSHostingController(rootView: RouletteView(model: model))
        host.sizingOptions = []
        let window = NSWindow(contentViewController: host)
        window.title = "Ruleta de Tickets"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(cgColor: Casino.feltDeep.cgColor()) ?? .black
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 1040, height: 780)
        window.setContentSize(NSSize(width: 1320, height: 900))
        window.center()
        watchSpaceBar(in: window, model: model)
        return window
    }

    /// Space spins, as on the web page, unless a text field or button has the keyboard.
    private func watchSpaceBar(in window: NSWindow, model: RouletteModel) {
        spaceBar = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak window] event in
            guard event.keyCode == Self.spaceKeyCode, let window, event.window === window,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                  !(window.firstResponder is NSText), !(window.firstResponder is NSButton) else { return event }
            model.spinWheel()
            return nil
        }
    }
}
