import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

enum DrawTool: String, CaseIterable, Identifiable {
    case pen, line, arrow, rectangle, ellipse, counter

    var id: Self { self }

    var symbol: String {
        switch self {
        case .pen: "pencil.tip"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .counter: "1.circle"
        }
    }

    var label: String {
        switch self {
        case .pen: "Pen"
        case .line: "Line"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .counter: "Numbered Marker"
        }
    }
}

struct DrawStroke: Identifiable {
    let id = UUID()
    var tool: DrawTool
    var color: Color
    var width: CGFloat
    var points: [CGPoint]
    var number = 0
}

final class DrawModel: ObservableObject {
    @Published var strokes: [DrawStroke] = []
    @Published var current: DrawStroke?
    @Published var tool: DrawTool = .pen
    /// When on, the canvas ignores the mouse so you can use apps underneath.
    @Published var clickThrough = false

    var nextNumber: Int { strokes.filter { $0.tool == .counter }.count + 1 }

    func undo() {
        if !strokes.isEmpty { strokes.removeLast() }
    }

    func clear() {
        strokes.removeAll()
        current = nil
    }
}

/// Full-screen annotation canvas on the screen under the mouse, plus a floating toolbar.
/// Exit with Esc, right-click, the toolbar's close button, or the hotkey.
final class DrawController {
    static let shared = DrawController()

    let model = DrawModel()
    private var canvas: DrawWindow?
    private var toolbar: OverlayPanel?
    private var clickThroughSink: AnyCancellable?

    func toggle() {
        canvas == nil ? start() : stop()
    }

    func start() {
        guard canvas == nil, let screen = NSScreen.withMouse else { return }
        model.clear()
        model.clickThrough = false

        let window = DrawWindow(frame: screen.frame)
        let host = InteractiveHostingView(rootView: DrawCanvasView(model: model, settings: .shared))
        host.onRightClick = { [weak self] in self?.stop() }
        window.contentView = host
        window.onEscape = { [weak self] in self?.stop() }
        window.onUndo = { [weak self] in self?.model.undo() }
        canvas = window

        let bar = InteractiveHostingView(rootView: DrawToolbarView(model: model, settings: .shared) { [weak self] in
            self?.stop()
        })
        let size = bar.fittingSize
        let panel = OverlayPanel(size: size)
        panel.ignoresMouseEvents = false
        panel.contentView = bar
        let vf = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.maxY - size.height - 12))
        toolbar = panel

        clickThroughSink = model.$clickThrough.sink { [weak window] on in
            window?.ignoresMouseEvents = on
        }

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func stop() {
        canvas?.orderOut(nil)
        toolbar?.orderOut(nil)
        canvas = nil
        toolbar = nil
        clickThroughSink = nil
        model.clear()
    }
}

final class DrawWindow: NSWindow {
    var onEscape: (() -> Void)?
    var onUndo: (() -> Void)?

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(frame, display: false)
        isOpaque = false
        // Nearly-clear rather than clear so the window still receives clicks.
        backgroundColor = NSColor(white: 0, alpha: 0.01)
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onEscape?()
        } else if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            onUndo?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

struct DrawCanvasView: View {
    @ObservedObject var model: DrawModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        Canvas { ctx, _ in
            for stroke in model.strokes { StrokeRenderer.draw(stroke, in: &ctx) }
            if let current = model.current { StrokeRenderer.draw(current, in: &ctx) }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged(dragChanged)
                .onEnded { _ in commit() }
        )
    }

    private func dragChanged(_ value: DragGesture.Value) {
        if model.current == nil {
            model.current = DrawStroke(
                tool: model.tool,
                color: settings.drawColor,
                width: settings.drawLineWidth,
                points: [value.startLocation],
                number: model.tool == .counter ? model.nextNumber : 0
            )
        }
        switch model.tool {
        case .pen:
            model.current?.points.append(value.location)
        case .line, .arrow, .rectangle, .ellipse:
            model.current?.points = [value.startLocation, value.location]
        case .counter:
            model.current?.points = [value.location]
        }
    }

    private func commit() {
        guard let stroke = model.current else { return }
        model.current = nil
        if stroke.tool == .pen || stroke.tool == .counter {
            model.strokes.append(stroke)
        } else if let a = stroke.points.first, let b = stroke.points.last, hypot(b.x - a.x, b.y - a.y) > 2 {
            model.strokes.append(stroke)
        }
    }
}

enum StrokeRenderer {
    static func draw(_ s: DrawStroke, in ctx: inout GraphicsContext) {
        let shading = GraphicsContext.Shading.color(s.color)
        let style = StrokeStyle(lineWidth: s.width, lineCap: .round, lineJoin: .round)
        guard let a = s.points.first, let b = s.points.last else { return }

        switch s.tool {
        case .pen:
            if s.points.count == 1 {
                let r = s.width / 2
                ctx.fill(Path(ellipseIn: CGRect(x: a.x - r, y: a.y - r, width: s.width, height: s.width)), with: shading)
                return
            }
            // Midpoint quadratic smoothing.
            var path = Path()
            path.move(to: a)
            for i in 1..<s.points.count {
                let p0 = s.points[i - 1], p1 = s.points[i]
                path.addQuadCurve(to: CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2), control: p0)
            }
            path.addLine(to: b)
            ctx.stroke(path, with: shading, style: style)

        case .line:
            ctx.stroke(Path { $0.move(to: a); $0.addLine(to: b) }, with: shading, style: style)

        case .arrow:
            let angle = atan2(b.y - a.y, b.x - a.x)
            let length = max(14, s.width * 4)
            let spread = CGFloat.pi / 7
            let left = CGPoint(x: b.x - length * cos(angle - spread), y: b.y - length * sin(angle - spread))
            let right = CGPoint(x: b.x - length * cos(angle + spread), y: b.y - length * sin(angle + spread))
            let base = CGPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
            ctx.stroke(Path { $0.move(to: a); $0.addLine(to: base) }, with: shading, style: style)
            ctx.fill(Path { $0.move(to: b); $0.addLine(to: left); $0.addLine(to: right); $0.closeSubpath() }, with: shading)

        case .rectangle:
            ctx.stroke(Path(rect(a, b)), with: shading, style: style)

        case .ellipse:
            ctx.stroke(Path(ellipseIn: rect(a, b)), with: shading, style: style)

        case .counter:
            let r = max(14, s.width * 3)
            ctx.fill(Path(ellipseIn: CGRect(x: b.x - r, y: b.y - r, width: r * 2, height: r * 2)), with: shading)
            ctx.draw(
                Text("\(s.number)").font(.system(size: r, weight: .bold, design: .rounded)).foregroundColor(.white),
                at: b
            )
        }
    }

    private static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}

struct DrawToolbarView: View {
    @ObservedObject var model: DrawModel
    @ObservedObject var settings: AppSettings
    let onClose: () -> Void

    private static let palette = ["#FF453A", "#FF9F0A", "#FFD60A", "#30D158", "#0A84FF", "#BF5AF2", "#FFFFFF", "#000000"]
    private static let widths: [Double] = [2, 5, 10]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DrawTool.allCases) { tool in
                ToolButton(symbol: tool.symbol, help: tool.label, selected: model.tool == tool) { model.tool = tool }
            }
            separator
            ForEach(Self.palette, id: \.self) { hex in
                let color = Color(hex: hex)
                let selected = color.hexString == settings.drawColor.hexString
                Button { settings.drawColor = color } label: {
                    Circle()
                        .fill(color)
                        .overlay(Circle().strokeBorder(.secondary.opacity(0.5), lineWidth: 1))
                        .frame(width: 18, height: 18)
                        .padding(3)
                        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0))
                        .frame(width: 26, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            separator
            ForEach(Self.widths, id: \.self) { w in
                Button { settings.drawLineWidth = w } label: {
                    Circle()
                        .fill(.primary)
                        .frame(width: w + 3, height: w + 3)
                        .frame(width: 26, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(settings.drawLineWidth == w ? Color.accentColor.opacity(0.25) : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Line width \(Int(w))")
            }
            separator
            ToolButton(symbol: "arrow.uturn.backward", help: "Undo (⌘Z)") { model.undo() }
            ToolButton(symbol: "trash", help: "Clear") { model.clear() }
            ToolButton(symbol: model.clickThrough ? "hand.point.up.left.fill" : "hand.point.up.left",
                       help: "Click through to apps (drawings stay)",
                       selected: model.clickThrough) { model.clickThrough.toggle() }
            ToolButton(symbol: "xmark", help: "Exit drawing (Esc or right-click)", action: onClose)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        )
        .padding(12)
    }

    private var separator: some View {
        Divider().frame(height: 22).padding(.horizontal, 4)
    }
}

private struct ToolButton: View {
    let symbol: String
    let help: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(selected ? Color.accentColor.opacity(0.25) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
