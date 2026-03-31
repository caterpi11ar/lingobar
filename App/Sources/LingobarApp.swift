import AppKit
import SwiftUI

@main
struct LingobarApp: App {
    @StateObject private var appModel: LingobarAppModel
    private let isUITestMode: Bool
    private let statusItemController: MenuBarStatusItemController?
    private let uiTestWindowController: UITestWindowController?
    private let settingsWindowController: SettingsWindowController?

    init() {
        let uiTestMode = ProcessInfo.processInfo.environment["LINGOBAR_UI_TEST_MODE"] == "1"
        let model = LingobarAppModel.bootstrap()
        _appModel = StateObject(wrappedValue: model)
        isUITestMode = uiTestMode
        settingsWindowController = uiTestMode ? nil : SettingsWindowController(model: model)
        statusItemController = uiTestMode ? nil : MenuBarStatusItemController(
            model: model,
            settingsWindowController: settingsWindowController
        )
        uiTestWindowController = uiTestMode ? UITestWindowController(model: model) : nil

        if uiTestMode {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        LingobarPrimaryScene(model: appModel)
    }
}

private struct LingobarPrimaryScene: Scene {
    @ObservedObject var model: LingobarAppModel

    var body: some Scene {
        Settings {
            SettingsRootView(model: model)
        }
    }
}
