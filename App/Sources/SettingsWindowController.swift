import AppKit
import Combine
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: LingobarAppModel
    private var window: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    init(model: LingobarAppModel) {
        self.model = model
        super.init()
        bindModel()
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    private func makeWindow() -> NSWindow {
        let hostingController = NSHostingController(
            rootView: SettingsRootView(model: model)
                .preferredColorScheme(model.preferredColorScheme)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Lingobar 设置"
        window.identifier = NSUserInterfaceItemIdentifier("lingobar-settings-window")
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        applyTheme(to: window)
        return window
    }

    private func bindModel() {
        model.$settings
            .map(\.theme)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let window = self.window else { return }
                self.applyTheme(to: window)
            }
            .store(in: &cancellables)
    }

    private func applyTheme(to window: NSWindow) {
        switch model.settings.theme {
        case .system:
            window.appearance = nil
        case .light:
            window.appearance = NSAppearance(named: .aqua)
        case .dark:
            window.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
