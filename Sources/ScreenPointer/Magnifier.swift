import AppKit
import Carbon.HIToolbox
import Combine
import CoreMedia
import QuartzCore
import ScreenCaptureKit

/// A round, click-through lens that follows the mouse and shows the screen under it magnified.
///
/// It streams the display under the mouse with ScreenCaptureKit (needs Screen Recording
/// permission), leaving out all of Screen Pointer's own windows (lens, halo, drawings,
/// keystrokes) so the lens never magnifies itself, and crops each frame to the region around
/// the cursor with `contentsRect`. Nothing is recorded or saved.
///
/// Magnifier shortcut (default ⌃⌥M): a quick tap toggles the lens; holding it shows the lens
/// only while held (this also works with a mouse button mapped to it). While the lens is
/// visible the zoom in/out and close shortcuts (default ⌃⌥= / ⌃⌥- / X) apply, and Esc closes it.
final class MagnifierController: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    static let shared = MagnifierController()

    @Published private(set) var isActive = false

    private let holdThreshold: TimeInterval = 0.35
    private let zoomStep = 1.25
    private var pressedAt: Date?
    private var activatedByThisPress = false

    private var panel: OverlayPanel?
    private let lensLayer = CALayer()
    private let ringLayer = CAShapeLayer()
    private var monitors: [Any] = []
    private var settingsSink: AnyCancellable?

    private var stream: SCStream?
    private var capturedDisplayID: CGDirectDisplayID?
    private var capturedFrame: NSRect = .zero
    private var restarting = false
    private let frameQueue = DispatchQueue(label: "ScreenPointer.magnifier.frames", qos: .userInteractive)

    // MARK: Hotkey behaviour

    func hotKeyPressed() {
        NSLog("Screen Pointer: magnifier hotkey pressed (active: \(isActive))")
        pressedAt = Date()
        if isActive {
            activatedByThisPress = false
            stop()
        } else {
            activatedByThisPress = true
            start()
        }
    }

    func hotKeyReleased() {
        defer { pressedAt = nil }
        guard activatedByThisPress, let pressedAt,
              Date().timeIntervalSince(pressedAt) >= holdThreshold else { return }
        NSLog("Screen Pointer: magnifier hotkey held, closing on release")
        stop() // held → momentary
    }

    func toggle() {
        isActive ? stop() : start()
    }

    // MARK: Lifecycle

    func start() {
        guard !isActive else { return }
        guard Permissions.hasScreenRecording else {
            Permissions.requestScreenRecording()
            return
        }
        isActive = true
        NSLog("Screen Pointer: magnifier on")

        let p = OverlayPanel(size: .zero)
        let host = NSView()
        host.wantsLayer = true
        host.layer?.addSublayer(lensLayer)
        host.layer?.addSublayer(ringLayer)
        p.contentView = host
        panel = p

        lensLayer.magnificationFilter = .linear
        lensLayer.masksToBounds = true
        lensLayer.backgroundColor = nil // see-through until the first frame lands
        ringLayer.fillColor = nil
        ringLayer.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        applyLensSize()
        p.orderFrontRegardless()

        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in self?.update() }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] in self?.update(); return $0 }) {
            monitors.append(m)
        }

        settingsSink = AppSettings.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.applyLensSize(); self?.update() }

        HotKeyCenter.shared.bind(.zoomIn) { [weak self] in self?.zoom(by: self?.zoomStep ?? 1) }
        HotKeyCenter.shared.bind(.zoomOut) { [weak self] in self?.zoom(by: 1 / (self?.zoomStep ?? 1)) }
        HotKeyCenter.shared.bind(.closeLens) { [weak self] in self?.stop() }
        HotKeyCenter.shared.bindEscape { [weak self] in self?.stop() }

        update() // starts capture for the screen under the mouse
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        NSLog("Screen Pointer: magnifier off")
        HotKeyCenter.shared.unbind([.zoomIn, .zoomOut, .closeLens])
        HotKeyCenter.shared.bindEscape(nil)
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        settingsSink = nil
        stopCapture()
        panel?.orderOut(nil)
        panel = nil
        lensLayer.contents = nil
    }

    private func zoom(by factor: Double) {
        let s = AppSettings.shared
        s.magnifierZoom = min(max(s.magnifierZoom * factor, 1.5), 10)
    }

    // MARK: Geometry

    private func applyLensSize() {
        let size = AppSettings.shared.magnifierSize
        let ring: CGFloat = 4
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        lensLayer.frame = bounds
        lensLayer.cornerRadius = size / 2
        ringLayer.frame = bounds
        ringLayer.lineWidth = ring
        ringLayer.path = CGPath(ellipseIn: bounds.insetBy(dx: ring / 2, dy: ring / 2), transform: nil)
        CATransaction.commit()
        panel?.setContentSize(NSSize(width: size, height: size))
    }

    /// Re-centres the lens on the mouse and crops the latest frame to the area under it.
    private func update() {
        guard isActive, let panel else { return }
        let mouse = NSEvent.mouseLocation
        let size = AppSettings.shared.magnifierSize
        panel.setFrameOrigin(NSPoint(x: mouse.x - size / 2, y: mouse.y - size / 2))

        if let screen = NSScreen.withMouse, screen.displayID != capturedDisplayID {
            restartCapture()
        }

        let f = capturedFrame
        guard f.width > 0, f.height > 0 else { return }
        // contentsRect is in unit coordinates with y=0 at the bottom, like Cocoa screen coordinates.
        let w = size / AppSettings.shared.magnifierZoom / f.width
        let h = size / AppSettings.shared.magnifierZoom / f.height
        let cx = (mouse.x - f.minX) / f.width
        let cy = (mouse.y - f.minY) / f.height
        let rect = CGRect(x: min(max(cx - w / 2, 0), max(1 - w, 0)),
                          y: min(max(cy - h / 2, 0), max(1 - h, 0)),
                          width: w, height: h)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lensLayer.contentsRect = rect
        CATransaction.commit()
    }

    // MARK: Capture

    private func restartCapture() {
        guard !restarting, let screen = NSScreen.withMouse, let displayID = screen.displayID else { return }
        restarting = true
        capturedDisplayID = displayID
        capturedFrame = screen.frame
        let scale = screen.backingScaleFactor
        let old = stream
        stream = nil

        Task { @MainActor in
            defer { self.restarting = false }
            try? await old?.stopCapture()
            guard self.isActive else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return }
                let ownApp = content.applications.filter { $0.processID == getpid() }
                let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])

                let config = SCStreamConfiguration()
                config.width = Int(CGFloat(display.width) * scale)
                config.height = Int(CGFloat(display.height) * scale)
                config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = false // the real cursor already sits at the lens centre
                config.queueDepth = 3 // the minimum; each full-screen frame is ~25 MB on Retina

                let s = SCStream(filter: filter, configuration: config, delegate: self)
                try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.frameQueue)
                try await s.startCapture()
                guard self.isActive else { try? await s.stopCapture(); return }
                self.stream = s
                self.update()
            } catch {
                NSLog("Screen Pointer: magnifier capture failed: \(error.localizedDescription)")
                self.stop()
            }
        }
    }

    private func stopCapture() {
        let s = stream
        stream = nil
        capturedDisplayID = nil
        Task { try? await s?.stopCapture() }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isActive, stream === self.stream else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.lensLayer.contents = surface
            CATransaction.commit()
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("Screen Pointer: magnifier stream stopped: \(error.localizedDescription)")
        DispatchQueue.main.async { [weak self] in
            if stream === self?.stream { self?.stop() }
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }
}
