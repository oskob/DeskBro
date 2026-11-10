import AppKit
import Carbon.HIToolbox
import ServiceManagement

/// A recorded keyboard shortcut.
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt // NSEvent.ModifierFlags raw value (command/option/control/shift only)

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if modifierFlags.contains(.command) { m |= UInt32(cmdKey) }
        if modifierFlags.contains(.option) { m |= UInt32(optionKey) }
        if modifierFlags.contains(.control) { m |= UInt32(controlKey) }
        if modifierFlags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    /// Human-readable, e.g. "⌥⌘D".
    var display: String {
        var s = ""
        if modifierFlags.contains(.control) { s += "⌃" }
        if modifierFlags.contains(.option) { s += "⌥" }
        if modifierFlags.contains(.shift) { s += "⇧" }
        if modifierFlags.contains(.command) { s += "⌘" }
        return s + Self.keyName(for: keyCode)
    }

    static let functionKeys: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    static func keyName(for keyCode: UInt16) -> String {
        if let f = functionKeys[keyCode] { return f }
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_DownArrow: return "↓"
        case kVK_UpArrow: return "↑"
        default: break
        }
        // Translate using the current keyboard layout so e.g. AZERTY shows the right letter.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "?"
        }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }

    /// ⌃⌥⌘D — not used by macOS (⌥⌘D toggles Dock hiding).
    static let defaultCombo = KeyCombo(keyCode: UInt16(kVK_ANSI_D),
                                       modifiers: NSEvent.ModifierFlags([.control, .option, .command]).rawValue)

    /// The old default, which clashed with the system's Dock shortcut.
    static let legacyDefaultCombo = KeyCombo(keyCode: UInt16(kVK_ANSI_D),
                                             modifiers: NSEvent.ModifierFlags([.option, .command]).rawValue)
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let showOnUnlock = "showOnUnlock"
        static let hotKey = "hotKey"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    private let defaults = UserDefaults.standard

    @Published var showOnUnlock: Bool {
        didSet { defaults.set(showOnUnlock, forKey: Keys.showOnUnlock) }
    }

    @Published var hotKey: KeyCombo? {
        didSet {
            if let hotKey, let data = try? JSONEncoder().encode(hotKey) {
                defaults.set(data, forKey: Keys.hotKey)
            } else {
                defaults.set(Data(), forKey: Keys.hotKey) // empty = explicitly cleared
            }
        }
    }

    /// True while the shortcut recorder is listening, so the global hotkey doesn't swallow the keys.
    @Published var isRecordingShortcut = false

    @Published private(set) var openAtLogin: Bool = SMAppService.mainApp.status == .enabled

    /// Set once the welcome flow is finished (so a quit halfway through shows it again).
    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }

    private init() {
        defaults.register(defaults: [Keys.showOnUnlock: true])
        showOnUnlock = defaults.bool(forKey: Keys.showOnUnlock)

        if let data = defaults.data(forKey: Keys.hotKey) {
            let saved = data.isEmpty ? nil : try? JSONDecoder().decode(KeyCombo.self, from: data)
            if saved?.keyCode == KeyCombo.legacyDefaultCombo.keyCode,
               saved?.modifiers == KeyCombo.legacyDefaultCombo.modifiers {
                hotKey = KeyCombo.defaultCombo
                defaults.removeObject(forKey: Keys.hotKey)
            } else {
                hotKey = saved
            }
        } else {
            hotKey = KeyCombo.defaultCombo
        }
    }

    /// Launch at login is strictly opt-in (App Store guideline 2.4.5).
    func setOpenAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled { try service.register() } else { try service.unregister() }
        } catch {
            NSSound.beep()
        }
        openAtLogin = service.status == .enabled
    }

    func refreshLoginStatus() {
        openAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// System-wide hotkey via Carbon's RegisterEventHotKey: works in the sandbox and needs no
/// Accessibility permission.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    private static var nextID: UInt32 = 1
    private let id: UInt32

    init(action: @escaping () -> Void) {
        self.action = action
        self.id = Self.nextID
        Self.nextID += 1
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let me = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            // Every instance's handler sees every hotkey; only react to our own.
            guard pressed.signature == GlobalHotKey.signature, pressed.id == me.id else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async { me.action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    private static let signature = OSType(0x4453_4B42) // "DSKB"

    func register(_ combo: KeyCombo?) {
        unregister()
        guard let combo else { return }
        RegisterEventHotKey(UInt32(combo.keyCode), combo.carbonModifiers,
                            EventHotKeyID(signature: Self.signature, id: id),
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    deinit {
        unregister()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
