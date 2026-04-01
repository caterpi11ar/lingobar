import AppKit
import SwiftUI

@main
struct LingobarApp: App {
    @StateObject private var appModel: LingobarAppModel
    private let statusItemController: MenuBarStatusItemController
    private let settingsWindowController: SettingsWindowController

    init() {
        let model = LingobarAppModel.bootstrap()
        _appModel = StateObject(wrappedValue: model)
        let settings = SettingsWindowController(model: model)
        settingsWindowController = settings
        statusItemController = MenuBarStatusItemController(
            model: model,
            settingsWindowController: settings
        )
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
