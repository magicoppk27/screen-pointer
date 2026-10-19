import SwiftUI

/// User preferences, persisted to UserDefaults. Controllers observe the
/// published values directly, so changing a setting takes effect immediately.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private static let store = UserDefaults.standard

    enum Default {
        static let cursorEnabled = true
        static let cursorSize = 56.0
        static let ringWidth = 3.0
        static let cursorColor = Color(hex: "#FFD60A")
        static let fillOpacity = 0.25
        static let inactiveOpacity = 0.35
        static let leftClickColor = Color(hex: "#FF453A")
        static let rightClickColor = Color(hex: "#0A84FF")
        static let keystrokesEnabled = false
        static let keystrokeFontSize = 28.0
        static let drawColor = Color(hex: "#FF453A")
        static let drawLineWidth = 5.0
    }

    // Cursor highlight
    @Published var cursorEnabled: Bool { didSet { save(cursorEnabled, "cursorEnabled") } }
    @Published var cursorSize: Double { didSet { save(cursorSize, "cursorSize") } }
    @Published var ringWidth: Double { didSet { save(ringWidth, "ringWidth") } }
    @Published var cursorColor: Color { didSet { save(cursorColor.hexString, "cursorColor") } }
    @Published var fillOpacity: Double { didSet { save(fillOpacity, "fillOpacity") } }
    @Published var inactiveOpacity: Double { didSet { save(inactiveOpacity, "inactiveOpacity") } }
    @Published var leftClickColor: Color { didSet { save(leftClickColor.hexString, "leftClickColor") } }
    @Published var rightClickColor: Color { didSet { save(rightClickColor.hexString, "rightClickColor") } }

    // Keystrokes
    @Published var keystrokesEnabled: Bool { didSet { save(keystrokesEnabled, "keystrokesEnabled") } }
    @Published var keystrokeFontSize: Double { didSet { save(keystrokeFontSize, "keystrokeFontSize") } }

    // Drawing
    @Published var drawColor: Color { didSet { save(drawColor.hexString, "drawColor") } }
    @Published var drawLineWidth: Double { didSet { save(drawLineWidth, "drawLineWidth") } }

    private init() {
        let d = Self.store
        cursorEnabled = d.object(forKey: "cursorEnabled") as? Bool ?? Default.cursorEnabled
        cursorSize = d.object(forKey: "cursorSize") as? Double ?? Default.cursorSize
        ringWidth = d.object(forKey: "ringWidth") as? Double ?? Default.ringWidth
        cursorColor = d.string(forKey: "cursorColor").map(Color.init(hex:)) ?? Default.cursorColor
        fillOpacity = d.object(forKey: "fillOpacity") as? Double ?? Default.fillOpacity
        inactiveOpacity = d.object(forKey: "inactiveOpacity") as? Double ?? Default.inactiveOpacity
        leftClickColor = d.string(forKey: "leftClickColor").map(Color.init(hex:)) ?? Default.leftClickColor
        rightClickColor = d.string(forKey: "rightClickColor").map(Color.init(hex:)) ?? Default.rightClickColor
        keystrokesEnabled = d.object(forKey: "keystrokesEnabled") as? Bool ?? Default.keystrokesEnabled
        keystrokeFontSize = d.object(forKey: "keystrokeFontSize") as? Double ?? Default.keystrokeFontSize
        drawColor = d.string(forKey: "drawColor").map(Color.init(hex:)) ?? Default.drawColor
        drawLineWidth = d.object(forKey: "drawLineWidth") as? Double ?? Default.drawLineWidth
    }

    func resetAppearance() {
        cursorSize = Default.cursorSize
        ringWidth = Default.ringWidth
        cursorColor = Default.cursorColor
        fillOpacity = Default.fillOpacity
        inactiveOpacity = Default.inactiveOpacity
        leftClickColor = Default.leftClickColor
        rightClickColor = Default.rightClickColor
        keystrokeFontSize = Default.keystrokeFontSize
        drawColor = Default.drawColor
        drawLineWidth = Default.drawLineWidth
    }

    private func save(_ value: Any, _ key: String) {
        Self.store.set(value, forKey: key)
    }
}
