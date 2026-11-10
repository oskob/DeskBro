import AppKit
import Combine
import SwiftUI

/// A non-activating panel: it can take keyboard focus (Esc, typing) even when macOS declines to
/// bring DeskBro to the front, which often happens for a background app right after unlock.
/// Borderless windows can't become key by default, hence the overrides.
final class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: OverlayWindow?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var keyMonitor: Any?
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private var isDismissing = false

    private let model = DashboardModel()
    private let settings = AppSettings.shared
    private var hotKey: GlobalHotKey?
    /// Esc as a system-wide hotkey while the dashboard is up, so it works even when macOS
    /// routes the keyboard to another app after unlock.
    private var escHotKey: GlobalHotKey?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpMainMenu()
        setUpStatusItem()
        setUpHotKey()
        observeUnlock()

        if !settings.hasCompletedOnboarding {
            showOnboarding()
        } else {
            Task { @MainActor in
                await model.requestAccess() // no prompt; just reads the current status
                if settings.showOnUnlock { showDashboard() }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings() // double-clicking the app in Finder opens Settings
        return false
    }

    // MARK: - Triggers

    private func observeUnlock() {
        // Undocumented but long-standing; fires after the user unlocks.
        DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleUnlockOrWake() }
        }
        // Documented fallback: when the display wakes. If the Mac is locked, the dashboard sits
        // ready behind the lock screen and is there the moment you unlock.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleUnlockOrWake() }
        }
    }

    private func handleUnlockOrWake() {
        guard settings.showOnUnlock, settings.hasCompletedOnboarding else { return }
        // Already up (e.g. shown on wake behind the lock screen): just take focus again.
        if let window, !isDismissing {
            focusDashboard(window)
            return
        }
        showDashboard()
    }

    private func setUpHotKey() {
        hotKey = GlobalHotKey { [weak self] in
            Task { @MainActor in self?.toggleDashboard() }
        }
        settings.$hotKey
            .combineLatest(settings.$isRecordingShortcut)
            .sink { [weak self] combo, recording in
                self?.hotKey?.register(recording ? nil : combo)
            }
            .store(in: &cancellables)
    }

    private func toggleDashboard() {
        if window != nil { dismiss() } else { showDashboard() }
    }

    // MARK: - Overlay

    @objc func showDashboard() {
        guard window == nil else { return }
        isDismissing = false
        settingsWindow?.orderOut(nil)
        Task { await model.reload() }

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let window = OverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = false
        window.setFrame(screen.frame, display: true)
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // Transparent: the dashboard paints its own background, so a fade never shows a black backdrop.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.alphaValue = 0
        window.contentView = NSHostingView(
            rootView: DashboardView(model: model, onDismiss: { [weak self] in self?.dismiss() })
        )

        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
        window.makeKeyAndOrderFront(nil)
        focusDashboard(window)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            window.animator().alphaValue = 1
        }

        if escHotKey == nil {
            escHotKey = GlobalHotKey { [weak self] in
                Task { @MainActor in self?.dismiss() }
            }
        }
        escHotKey?.register(KeyCombo(keyCode: 53, modifiers: 0)) // Esc

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.dismiss()
                return nil
            }
            return event
        }

        // Keep data fresh while the dashboard is on screen.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.model.reload() }
        }

        self.window = window
    }

    /// Makes the dashboard the key window and asks macOS to activate DeskBro. Activation can be
    /// refused for background apps; the non-activating panel still receives keys either way.
    private func focusDashboard(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // Activation is asynchronous and may be refused at first; try again a moment later.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak window] in
            guard let window, self?.window === window, !window.isKeyWindow else { return }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
    }

    func dismiss() {
        guard let window, !isDismissing else { return }
        isDismissing = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self, weak window] in
            MainActor.assumeIsolated {
                guard let self, let window, self.window === window else { return }
                self.tearDown()
            }
        })
        // Animations may never complete (e.g. while the display sleeps); don't get stuck half-dismissed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            self.tearDown()
        }
    }

    private func tearDown() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        escHotKey?.unregister()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
        NSApp.presentationOptions = []
        if settingsWindow?.isVisible != true {
            NSApp.hide(nil) // hand focus back to whatever you were using
        }
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        let view = OnboardingView(model: model, settings: settings) { [weak self] in
            guard let self else { return }
            self.settings.hasCompletedOnboarding = true
            self.onboardingWindow?.close()
            self.onboardingWindow = nil
            self.showDashboard()
        }
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.backgroundColor = NSColor(Theme.bgTop)
        w.isReleasedWhenClosed = false
        w.center()
        onboardingWindow = w
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }

    // MARK: - Settings window

    @objc func openSettings() {
        if window != nil { tearDown() }
        if settingsWindow == nil {
            let controller = NSHostingController(
                rootView: SettingsView(settings: settings, onShowDashboard: { [weak self] in self?.showDashboard() })
            )
            let w = NSWindow(contentViewController: controller)
            w.title = "DeskBro Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Menus

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.inset.filled", accessibilityDescription: "DeskBro")

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Dashboard", action: #selector(showDashboard), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit DeskBro", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    /// Accessory apps have no visible menu bar, but a main menu still gives windows ⌘W/⌘Q/⌘,.
    private func setUpMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit DeskBro", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}
