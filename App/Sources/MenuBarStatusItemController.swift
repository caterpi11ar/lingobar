import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarStatusItemController: NSObject {
    private let popoverWidth: CGFloat = 360
    private let minPopoverHeight: CGFloat = 220
    private let maxPopoverHeight: CGFloat = 560
    private let model: LingobarAppModel
    private let settingsWindowController: SettingsWindowController?
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var cancellables: Set<AnyCancellable> = []
    private var customStatusImage: NSImage?
    private var loadingTimer: Timer?
    private var loadingFrame = 0

    init(model: LingobarAppModel, settingsWindowController: SettingsWindowController?) {
        self.model = model
        self.settingsWindowController = settingsWindowController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()
        configureStatusItem()
        configurePopover()
        bindModel()
        loadStatusIcon()
        refreshStatusItem()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp])
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleNone
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: popoverWidth, height: minPopoverHeight)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView(
                model: model,
                onOpenSettings: { [weak self] in
                    self?.openSettings()
                },
                onQuit: {
                    NSApp.terminate(nil)
                }
            )
        )
        updatePopoverSize()
        applyPopoverTheme()
    }

    private func bindModel() {
        model.$translationRuntimeState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshStatusItem()
                if self?.popover.isShown == true {
                    self?.updatePopoverSize()
                }
            }
            .store(in: &cancellables)

        model.$settings
            .map(\.theme)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyPopoverTheme()
            }
            .store(in: &cancellables)
    }

    private func refreshStatusItem() {
        updateLoadingTimer()

        guard let button = statusItem.button else { return }
        let title = currentTitle()
        let image = currentStatusImage(title: title)
        button.image = image
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            ]
        )
        button.toolTip = model.menuBarTooltip
    }

    private func loadStatusIcon() {
        MenuBarIconLoader.load { [weak self] image in
            guard let self, let image else { return }
            self.customStatusImage = image
            self.refreshStatusItem()
        }
    }

    private func currentStatusImage(title: String) -> NSImage? {
        if let customStatusImage {
            customStatusImage.size = NSSize(width: 16, height: 16)
            customStatusImage.isTemplate = false
            return customStatusImage
        }

        let fallback = NSImage(
            systemSymbolName: model.menuBarSymbolName,
            accessibilityDescription: title
        )
        fallback?.isTemplate = true
        return fallback
    }

    private func currentTitle() -> String {
        let base = model.menuBarCompactText
        guard model.translationRuntimeState.phase.isLoading else { return base }
        let dots = String(repeating: "·", count: max(1, loadingFrame))
        return "\(base)\(dots)"
    }

    private func updateLoadingTimer() {
        guard model.translationRuntimeState.phase.isLoading else {
            loadingTimer?.invalidate()
            loadingTimer = nil
            loadingFrame = 0
            return
        }

        guard loadingTimer == nil else { return }
        loadingFrame = 1
        loadingTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.loadingFrame = self.loadingFrame % 3 + 1
                self.refreshStatusItem()
            }
        }
    }

    @objc
    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            updatePopoverSize()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updatePopoverSize() {
        guard let view = popover.contentViewController?.view else { return }
        view.frame.size.width = popoverWidth
        view.layoutSubtreeIfNeeded()

        let fittingHeight = view.fittingSize.height
        let clampedHeight = min(max(fittingHeight, minPopoverHeight), maxPopoverHeight)
        popover.contentSize = NSSize(width: popoverWidth, height: clampedHeight)
    }

    private func openSettings() {
        popover.performClose(nil)
        settingsWindowController?.show()
    }

    private func applyPopoverTheme() {
        switch model.settings.theme {
        case .system:
            popover.appearance = nil
            popover.contentViewController?.view.appearance = nil
        case .light:
            let appearance = NSAppearance(named: .aqua)
            popover.appearance = appearance
            popover.contentViewController?.view.appearance = appearance
        case .dark:
            let appearance = NSAppearance(named: .darkAqua)
            popover.appearance = appearance
            popover.contentViewController?.view.appearance = appearance
        }
    }
}
