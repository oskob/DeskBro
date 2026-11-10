import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let onShowDashboard: () -> Void

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "rectangle.inset.filled")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            LinearGradient(colors: [Color(red: 0.4, green: 0.45, blue: 1), Color(red: 0.75, green: 0.35, blue: 0.85)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DeskBro").font(.headline)
                        Text("Your day, front and center.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Show Dashboard", action: onShowDashboard)
                }
                .padding(.vertical, 4)
            }

            Section {
                Toggle(isOn: $settings.showOnUnlock) {
                    Text("Show full screen when I unlock my Mac")
                    Text("The dashboard covers the screen after unlocking or waking from sleep.")
                }
                Toggle(isOn: Binding(
                    get: { settings.openAtLogin },
                    set: { settings.setOpenAtLogin($0) }
                )) {
                    Text("Open DeskBro at login")
                    Text("Needed for the unlock dashboard to work after a restart.")
                }
            } header: {
                Text("Behavior")
            }

            Section {
                LabeledContent {
                    ShortcutRecorder(combo: $settings.hotKey, isRecording: $settings.isRecordingShortcut)
                } label: {
                    Text("Show / hide dashboard")
                    Text("Works from any app.")
                }
            } header: {
                Text("Keyboard Shortcut")
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { settings.refreshLoginStatus() }
    }
}

/// Click, then press a key combination. Esc cancels, ⌫ clears.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    @Binding var isRecording: Bool
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggle) {
                Text(label)
                    .font(.system(.body, design: combo == nil || isRecording ? .default : .rounded).weight(.medium))
                    .foregroundStyle(isRecording ? Color.accentColor : (combo == nil ? .secondary : .primary))
                    .frame(minWidth: 130)
            }
            .controlSize(.large)

            if combo != nil && !isRecording {
                Button {
                    combo = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private var label: String {
        if isRecording { return "Type shortcut…" }
        return combo?.display ?? "Record Shortcut"
    }

    private func toggle() {
        isRecording ? stop() : start()
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])

            if mods.isEmpty && event.keyCode == 53 { // Esc
                stop()
                return nil
            }
            if mods.isEmpty && (event.keyCode == 51 || event.keyCode == 117) { // ⌫ / ⌦
                combo = nil
                stop()
                return nil
            }
            let isFunctionKey = KeyCombo.functionKeys[event.keyCode] != nil
            if mods.intersection([.command, .option, .control]).isEmpty && !isFunctionKey {
                NSSound.beep() // needs ⌘, ⌥ or ⌃ so it doesn't hijack normal typing
                return nil
            }
            combo = KeyCombo(keyCode: event.keyCode, modifiers: mods.rawValue)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}
