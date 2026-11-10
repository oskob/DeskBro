// Renders the README animation frames: locked Mac → unlock → DeskBro dashboard → dismiss → desktop.
// Compiled together with the app's DashboardView/DashboardModel by render.sh, so the dashboard
// shown is the real UI, filled with example data.
//
// Usage: readme-demo <frames-dir> <app-icon.png>

import AppKit
import SwiftUI

let args = CommandLine.arguments
let framesDir = URL(fileURLWithPath: args[1])
let appIcon = NSImage(contentsOfFile: args[2]) ?? NSImage()

// MARK: - Geometry

/// Virtual screen sizes. Smaller than a real Mac's so the UI reads at README size —
/// this is a depiction of the flow, not a pixel-accurate screenshot.
let screenSize = CGSize(width: 945, height: 614)      // lock screen + desktop (~1.6× a 14" MBP)
let dashboardSize = CGSize(width: 1300, height: 844)  // the real dashboard view (~1.15×)
/// The whole animation canvas, in points (rendered @2x).
let canvas = CGSize(width: 820, height: 560)
let outputScale: CGFloat = 2
/// Where the screen sits inside the laptop on the canvas.
let screenRect = CGRect(x: 92, y: 34, width: 636, height: 413)
let fps = 20.0

// MARK: - Example data

var calendar = Calendar(identifier: .gregorian)
calendar.locale = Locale(identifier: "en_GB")
calendar.firstWeekday = 2
func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}
let now = date(10, 9, 41)

let work = Color(red: 0.40, green: 0.60, blue: 1.00)
let personal = Color(red: 0.45, green: 0.82, blue: 0.55)
let family = Color(red: 0.96, green: 0.52, blue: 0.72)
let social = Color(red: 1.00, green: 0.76, blue: 0.32)

func event(_ title: String, _ start: Date, _ end: Date, _ cal: String, _ color: Color,
           allDay: Bool = false, location: String? = nil) -> EventItem {
    EventItem(id: title + "\(start.timeIntervalSince1970)", title: title, start: start, end: end,
              isAllDay: allDay, location: location, calendarName: cal, color: color)
}

let weekEvents: [EventItem] = [
    event("Sprint planning", date(9, 10), date(9, 11), "Work", work),
    event("Gym", date(9, 18), date(9, 19), "Personal", personal),
    event("Mum’s birthday", date(10, 0), date(11, 0), "Family", family, allDay: true),
    event("Morning run", date(10, 7, 30), date(10, 8, 15), "Personal", personal),
    event("Design review", date(10, 9, 30), date(10, 10, 15), "Work", work, location: "Room 4B"),
    event("Lunch with Sam", date(10, 12), date(10, 13), "Social", social, location: "Café Pascal"),
    event("1:1 with Alex", date(10, 15), date(10, 15, 30), "Work", work),
    event("Climbing", date(10, 18, 30), date(10, 20), "Personal", personal),
    event("Dentist", date(11, 8, 30), date(11, 9), "Personal", personal),
    event("Team offsite", date(12, 9), date(12, 16), "Work", work),
    event("Dinner with Jo", date(12, 19), date(12, 21), "Social", social),
    event("Release day", date(13, 10), date(13, 11), "Work", work),
    event("Friday drinks", date(13, 17), date(13, 19), "Social", social),
    event("Farmers market", date(14, 9), date(14, 11), "Personal", personal),
    event("Brunch at Nora’s", date(15, 11), date(15, 13), "Family", family),
]
let todayStart = calendar.startOfDay(for: now)
let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)!
let todayEvents = weekEvents
    .filter { $0.start < todayEnd && $0.end > todayStart }
    .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }

let reminders: [ReminderItem] = [
    ReminderItem(id: "1", title: "Send invoice to Northwind", due: date(9, 0), dueHasTime: false,
                 listName: "Work", color: work, priority: 1),
    ReminderItem(id: "2", title: "Book flights to Lisbon", due: date(10, 17), dueHasTime: true,
                 listName: "Personal", color: personal, priority: 0),
    ReminderItem(id: "3", title: "Reply to Maya about the conference talk", due: nil, dueHasTime: false,
                 listName: "Work", color: work, priority: 0),
    ReminderItem(id: "4", title: "Pick up dry cleaning", due: nil, dueHasTime: false,
                 listName: "Errands", color: social, priority: 0),
    ReminderItem(id: "5", title: "Renew passport", due: date(13, 0), dueHasTime: false,
                 listName: "Personal", color: personal, priority: 0),
    ReminderItem(id: "6", title: "Water the plants", due: nil, dueHasTime: false,
                 listName: "Home", color: family, priority: 0),
]

// MARK: - Rendering helper

@MainActor
func render<V: View>(_ view: V, size: CGSize, pixelScale: CGFloat) -> NSBitmapImageRep {
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
    host.frame = CGRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.02)) // let SwiftUI commit a frame

    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(size.width * pixelScale), pixelsHigh: Int(size.height * pixelScale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    host.cacheDisplay(in: host.bounds, to: rep)
    return rep
}

@MainActor
func renderSwiftUI<V: View>(_ view: V, size: CGSize, pixelScale: CGFloat) -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = pixelScale
    renderer.isOpaque = false
    let rep = NSBitmapImageRep(cgImage: renderer.cgImage!)
    rep.size = size
    return rep
}

func image(_ rep: NSBitmapImageRep) -> NSImage {
    let img = NSImage(size: rep.size)
    img.addRepresentation(rep)
    return img
}

// MARK: - macOS chrome (simplified)

struct Wallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.13, blue: 0.32),
                                    Color(red: 0.30, green: 0.16, blue: 0.42)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color(red: 0.25, green: 0.55, blue: 0.95).opacity(0.75))
                .frame(width: 560).blur(radius: 100).offset(x: -260, y: -160)
            Circle().fill(Color(red: 0.95, green: 0.45, blue: 0.55).opacity(0.55))
                .frame(width: 500).blur(radius: 105).offset(x: 290, y: 190)
            Circle().fill(Color(red: 0.35, green: 0.85, blue: 0.80).opacity(0.35))
                .frame(width: 380).blur(radius: 95).offset(x: 190, y: -200)
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .clipped()
    }
}

struct StatusIcons: View {
    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "wifi")
            Image(systemName: "battery.100")
        }
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(.white)
    }
}

struct LockScreen: View {
    let dots: Int // 0...6 typed password characters

    var body: some View {
        ZStack {
            Wallpaper()
            VStack(spacing: 0) {
                HStack { Spacer(); StatusIcons() }
                    .padding(.horizontal, 20).padding(.top, 12)
                Text("Tuesday 10 November")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 34)
                Text("9:41")
                    .font(.system(size: 130, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.top, -10)
                Spacer()
                VStack(spacing: 14) {
                    Circle()
                        .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.65, blue: 0.95), Color(red: 0.40, green: 0.45, blue: 0.85)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 72, height: 72)
                        .overlay(Text("O")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white))
                    Text("Oskar")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                    ZStack {
                        Capsule().fill(.white.opacity(0.22))
                        if dots == 0 {
                            Text("Enter Password")
                                .font(.system(size: 17))
                                .foregroundStyle(.white.opacity(0.6))
                        } else {
                            HStack(spacing: 7) {
                                ForEach(0..<dots, id: \.self) { _ in
                                    Circle().fill(.white).frame(width: 10, height: 10)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 18)
                        }
                    }
                    .frame(width: 250, height: 42)
                    Text("Touch ID or Enter Password")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.bottom, 40)
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
    }
}

struct DockIcon: View {
    let symbol: String
    let colors: [Color]

    var body: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .frame(width: 58, height: 58)
            .overlay(Image(systemName: symbol)
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(.white))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}

struct Desktop: View {
    var body: some View {
        ZStack(alignment: .top) {
            Wallpaper()

            // Menu bar
            HStack(spacing: 18) {
                Image(systemName: "apple.logo").font(.system(size: 18))
                Text("Finder").fontWeight(.bold)
                ForEach(["File", "Edit", "View", "Window"], id: \.self) { Text($0) }
                Spacer()
                Image(systemName: "rectangle.inset.filled") // DeskBro's menu bar icon
                StatusIcons()
                Text("Tue 9:41")
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 34)
            .background(Color.black.opacity(0.22))

            // Dock
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    DockIcon(symbol: "face.smiling", colors: [Color(red: 0.35, green: 0.70, blue: 1), Color(red: 0.15, green: 0.45, blue: 0.95)])
                    DockIcon(symbol: "safari", colors: [Color(red: 0.30, green: 0.80, blue: 1), Color(red: 0.10, green: 0.50, blue: 0.95)])
                    DockIcon(symbol: "envelope.fill", colors: [Color(red: 0.40, green: 0.75, blue: 1), Color(red: 0.15, green: 0.50, blue: 1)])
                    DockIcon(symbol: "calendar", colors: [Color(white: 0.98), Color(white: 0.88)])
                        .overlay(Image(systemName: "calendar").font(.system(size: 27, weight: .medium)).foregroundStyle(.red))
                    DockIcon(symbol: "checklist", colors: [Color(white: 0.98), Color(white: 0.88)])
                        .overlay(Image(systemName: "checklist").font(.system(size: 27, weight: .medium)).foregroundStyle(.orange))
                    DockIcon(symbol: "gearshape.fill", colors: [Color(white: 0.65), Color(white: 0.45)])
                    Rectangle().fill(.white.opacity(0.3)).frame(width: 1, height: 46).padding(.horizontal, 4)
                    Image(nsImage: appIcon)
                        .resizable().interpolation(.high)
                        .frame(width: 70, height: 70)
                        .padding(-6)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.white.opacity(0.20))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(.white.opacity(0.25), lineWidth: 1))
                )
                .padding(.bottom, 8)
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
    }
}

/// Classic macOS arrow pointer.
struct Pointer: View {
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 0, y: 17))
            p.addLine(to: CGPoint(x: 4.2, y: 13.2))
            p.addLine(to: CGPoint(x: 7, y: 19.5))
            p.addLine(to: CGPoint(x: 9.6, y: 18.4))
            p.addLine(to: CGPoint(x: 6.9, y: 12.2))
            p.addLine(to: CGPoint(x: 12.4, y: 12.2))
            p.closeSubpath()
        }
        .fill(.black)
        .overlay(
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: 0, y: 17))
                p.addLine(to: CGPoint(x: 4.2, y: 13.2))
                p.addLine(to: CGPoint(x: 7, y: 19.5))
                p.addLine(to: CGPoint(x: 9.6, y: 18.4))
                p.addLine(to: CGPoint(x: 6.9, y: 12.2))
                p.addLine(to: CGPoint(x: 12.4, y: 12.2))
                p.closeSubpath()
            }
            .stroke(.white, style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
        )
        .frame(width: 13, height: 20, alignment: .topLeading)
        .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
    }
}

// MARK: - Laptop

struct Laptop<Screen: View>: View {
    @ViewBuilder let screen: Screen

    var body: some View {
        let bezel: CGFloat = 13
        let lid = screenRect.insetBy(dx: -bezel, dy: -bezel)
        ZStack(alignment: .topLeading) {
            // Floor shadow
            Ellipse()
                .fill(.black.opacity(0.35))
                .frame(width: lid.width * 1.05, height: 26)
                .blur(radius: 14)
                .offset(x: lid.minX - lid.width * 0.025, y: lid.maxY + 6)

            // Lid with a thin aluminium edge
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.05, green: 0.05, blue: 0.06))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color(white: 0.62), Color(white: 0.32)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 2))
                .frame(width: lid.width, height: lid.height)
                .offset(x: lid.minX, y: lid.minY)

            // Screen
            screen
                .frame(width: screenRect.width, height: screenRect.height)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 11, bottomLeadingRadius: 4,
                                                  bottomTrailingRadius: 4, topTrailingRadius: 11,
                                                  style: .continuous))
                .offset(x: screenRect.minX, y: screenRect.minY)

            // Camera notch
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 6,
                                   bottomTrailingRadius: 6, topTrailingRadius: 0, style: .continuous)
                .fill(Color(red: 0.05, green: 0.05, blue: 0.06))
                .frame(width: 78, height: 13)
                .offset(x: screenRect.midX - 39, y: screenRect.minY)

            // Base
            let baseWidth = lid.width * 1.13
            let baseX = lid.midX - baseWidth / 2
            UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 14,
                                   bottomTrailingRadius: 14, topTrailingRadius: 3, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.80), Color(white: 0.62), Color(white: 0.42)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: baseWidth, height: 15)
                .offset(x: baseX, y: lid.maxY - 1)
            // Thumb notch
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 5,
                                   bottomTrailingRadius: 5, topTrailingRadius: 0, style: .continuous)
                .fill(Color(white: 0.50))
                .frame(width: 110, height: 6)
                .offset(x: lid.midX - 55, y: lid.maxY - 1)
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
    }
}

// MARK: - Timeline

func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
func progress(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp((t - a) / (b - a)) }
func ease(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }

struct Frame: View {
    let t: Double
    let lock: [NSImage]
    let dashboard: NSImage
    let desktop: NSImage

    // Seconds
    static let duration = 8.2

    var body: some View {
        // Locked: type password 0.4–1.2, unlock 1.5–2.0 straight into DeskBro (it's already up
        // behind the lock screen), pointer moves to Dismiss 4.4–5.4, click 5.6, dashboard fades
        // 5.7–6.1 to the desktop, then the Mac locks again 7.6–8.2 for a seamless loop.
        let dots = Int((progress(t, 0.4, 1.2) * 6).rounded(.down))
        let unlock = ease(progress(t, 1.5, 2.0))
        let relock = ease(progress(t, 7.6, 8.2))
        let lockOpacity = max(1 - unlock, relock)
        let dashIn = t >= 1.5 ? 1.0 : 0.0
        let dashOut = ease(progress(t, 5.75, 6.15))
        let dashOpacity = dashIn * (1 - dashOut)

        // Pointer, as fractions of the screen
        let start = CGPoint(x: 0.55, y: 0.58)
        let target = CGPoint(x: (dashboardSize.width - 54 - 38) / dashboardSize.width, // right end of Dismiss
                             y: (52 + 22) / dashboardSize.height)
        let move = ease(progress(t, 4.4, 5.4))
        let pointer = CGPoint(x: start.x + (target.x - start.x) * move,
                              y: start.y + (target.y - start.y) * move)
        let pointerOpacity = progress(t, 4.1, 4.4) * (1 - relock)
        let click = progress(t, 5.55, 5.95)

        let w = screenRect.width, h = screenRect.height

        Laptop {
            ZStack(alignment: .topLeading) {
                Image(nsImage: desktop).resizable()
                Image(nsImage: dashboard).resizable()
                    .opacity(dashOpacity)
                    .scaleEffect(1 + 0.01 * dashOut)
                Image(nsImage: lock[relock > 0 ? 6 : dots]).resizable()
                    .opacity(lockOpacity)
                    .scaleEffect(1 + 0.05 * unlock * (1 - relock))
                    .blur(radius: 10 * unlock * (1 - relock))

                // Click ripple + pointer
                Circle()
                    .strokeBorder(Theme.accent, lineWidth: 2)
                    .frame(width: 14 + 40 * click, height: 14 + 40 * click)
                    .opacity(click > 0 && click < 1 ? (1 - click) * 0.9 : 0)
                    .position(x: target.x * w, y: target.y * h)
                Pointer()
                    .scaleEffect(click > 0 && click < 0.35 ? 1.4 : 1.65, anchor: .topLeading)
                    .offset(x: pointer.x * w, y: pointer.y * h)
                    .opacity(pointerOpacity)
            }
            .frame(width: screenRect.width, height: screenRect.height, alignment: .topLeading)
        }
    }
}

// MARK: - Main

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)

    // Render each screen once at the laptop screen's pixel size, then composite per frame.
    let screenPixelScale = screenRect.width * outputScale / screenSize.width

    let model = DashboardModel()
    model.calendarAccess = .granted
    model.remindersAccess = .granted
    model.events = todayEvents
    model.weekEvents = weekEvents
    model.reminders = reminders

    let dashboard = image(render(DashboardView(model: model, onDismiss: {}, fixedNow: now),
                                 size: dashboardSize,
                                 pixelScale: screenRect.width * outputScale / dashboardSize.width))
    let desktop = image(renderSwiftUI(Desktop(), size: screenSize, pixelScale: screenPixelScale))
    let lock = (0...6).map { image(renderSwiftUI(LockScreen(dots: $0), size: screenSize, pixelScale: screenPixelScale)) }

    // Full-size still of the dashboard for the README.
    let still = render(DashboardView(model: model, onDismiss: {}, fixedNow: now),
                       size: CGSize(width: 1512, height: 982), pixelScale: 1.5)
    try! still.representation(using: .png, properties: [:])!
        .write(to: framesDir.deletingLastPathComponent().appendingPathComponent("dashboard.png"))

    try? FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)
    let count = Int(Frame.duration * fps)
    for i in 0..<count {
        let rep = renderSwiftUI(Frame(t: Double(i) / fps, lock: lock, dashboard: dashboard, desktop: desktop),
                                size: canvas, pixelScale: outputScale)
        let url = framesDir.appendingPathComponent(String(format: "frame_%04d.png", i))
        try! rep.representation(using: .png, properties: [:])!.write(to: url)
    }
    print("Rendered \(count) frames")
}
