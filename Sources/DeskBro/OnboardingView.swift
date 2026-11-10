import SwiftUI

/// First-run flow: welcome → Calendar/Reminders access → behavior (login item is opt-in).
struct OnboardingView: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject var settings: AppSettings
    let onFinish: () -> Void

    @State private var step = 0
    @State private var requesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sun.max")
                    .font(.system(size: 13, weight: .semibold))
                Text("DESKBRO")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(3.2)
                Spacer()
                StepDots(count: 3, current: step)
            }
            .foregroundStyle(Theme.accent)
            .padding(.bottom, 36)

            Group {
                switch step {
                case 0: welcome
                case 1: access
                default: behavior
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 44)
        .padding(.top, 44)
        .padding(.bottom, 36)
        .frame(width: 580, height: 560)
        .background(LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom))
        .preferredColorScheme(.dark)
    }

    private func next() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { step += 1 }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your day,\nfront and center.")
                .font(.system(size: 46, weight: .regular, design: .serif))
                .foregroundStyle(Theme.text)
                .lineSpacing(2)
            Text("DeskBro shows today’s agenda and your reminders full screen every time you unlock your Mac, so nothing slips by. Glance, tick things off, press esc.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.secondary)
                .lineSpacing(4)
                .padding(.top, 20)
                .frame(maxWidth: 440, alignment: .leading)
            Spacer()
            PrimaryButton(title: "Get started", action: next)
        }
    }

    private var access: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Connect your day")
                .font(.system(size: 38, weight: .regular, design: .serif))
                .foregroundStyle(Theme.text)
            Text("DeskBro reads your calendars and reminders. Everything stays on this Mac.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 12)

            VStack(spacing: 0) {
                AccessRow(symbol: "calendar", title: "Calendar", detail: "Today’s events and your week", state: model.calendarAccess)
                Rectangle().fill(Theme.divider).frame(height: 1)
                AccessRow(symbol: "checklist", title: "Reminders", detail: "View, add and tick off reminders", state: model.remindersAccess)
            }
            .padding(.horizontal, 20)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cardBorder))
            .padding(.top, 28)

            if model.calendarAccess == .denied || model.remindersAccess == .denied {
                Text("You can change this later in System Settings → Privacy & Security.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.tertiary)
                    .padding(.top, 14)
            }

            Spacer()

            if model.calendarAccess == .unknown || model.remindersAccess == .unknown {
                PrimaryButton(title: requesting ? "Waiting…" : "Allow access") {
                    requesting = true
                    Task {
                        await model.requestAccess()
                        requesting = false
                    }
                }
                .disabled(requesting)
            } else {
                PrimaryButton(title: "Continue", action: next)
            }
        }
    }

    private var behavior: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Make it a habit")
                .font(.system(size: 38, weight: .regular, design: .serif))
                .foregroundStyle(Theme.text)
            Text("Choose when DeskBro shows up. You can change these anytime from the menu bar icon.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 12)

            VStack(spacing: 0) {
                OptionRow(title: "Open DeskBro at login",
                          detail: "Recommended. Keeps DeskBro running so it can greet you on unlock.") {
                    Toggle("", isOn: Binding(get: { settings.openAtLogin },
                                             set: { settings.setOpenAtLogin($0) }))
                        .toggleStyle(.switch).tint(Theme.accent).labelsHidden()
                }
                Rectangle().fill(Theme.divider).frame(height: 1)
                OptionRow(title: "Show full screen on unlock",
                          detail: "Covers the screen after you unlock or wake your Mac.") {
                    Toggle("", isOn: $settings.showOnUnlock)
                        .toggleStyle(.switch).tint(Theme.accent).labelsHidden()
                }
                Rectangle().fill(Theme.divider).frame(height: 1)
                OptionRow(title: "Keyboard shortcut", detail: "Show or hide the dashboard from any app.") {
                    ShortcutRecorder(combo: $settings.hotKey, isRecording: $settings.isRecordingShortcut)
                }
            }
            .padding(.horizontal, 20)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cardBorder))
            .padding(.top, 28)

            Spacer()
            PrimaryButton(title: "Show my dashboard", action: onFinish)
        }
        .onAppear { settings.refreshLoginStatus() }
    }
}

// MARK: - Pieces

private struct StepDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Theme.accent : Theme.accent.opacity(0.25))
                    .frame(width: i == current ? 18 : 6, height: 6)
            }
        }
        .animation(.spring(response: 0.4), value: current)
    }
}

private struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(Theme.accentInk)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(Theme.accent.opacity(isEnabled ? (hovering ? 1 : 0.92) : 0.5), in: Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .onHover { hovering = $0 }
    }
}

private struct AccessRow: View {
    let symbol: String
    let title: String
    let detail: String
    let state: AccessState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.text)
                Text(detail).font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            switch state {
            case .granted:
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            case .denied:
                Label("Not allowed", systemImage: "xmark.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.danger)
            case .unknown:
                EmptyView()
            }
        }
        .padding(.vertical, 16)
    }
}

private struct OptionRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.text)
                Text(detail).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            control
        }
        .padding(.vertical, 14)
    }
}
