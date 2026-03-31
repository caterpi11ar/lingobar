import AppKit
import Combine
import LingobarDomain
import SwiftUI

@MainActor
final class UITestWindowController: NSObject {
    private let window: NSWindow
    private var cancellables: Set<AnyCancellable> = []

    init(model: LingobarAppModel) {
        let contentView = SettingsRootView(model: model)
            .preferredColorScheme(model.preferredColorScheme)
        let hostingController = NSHostingController(rootView: contentView)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = "Lingobar Test Window"
        window.identifier = NSUserInterfaceItemIdentifier("lingobar-ui-test-window")
        window.contentViewController = hostingController
        applyTheme(theme: model.settings.theme)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        bindModel(model)
    }

    private func bindModel(_ model: LingobarAppModel) {
        model.$settings
            .map(\.theme)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] theme in
                self?.applyTheme(theme: theme)
            }
            .store(in: &cancellables)
    }

    private func applyTheme(theme: ThemeMode) {
        switch theme {
        case .system:
            window.appearance = nil
        case .light:
            window.appearance = NSAppearance(named: .aqua)
        case .dark:
            window.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
