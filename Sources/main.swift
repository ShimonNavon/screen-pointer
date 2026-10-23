import AppKit
import Carbon.HIToolbox
import SwiftUI

// Screen Pointer — a capturable, never-focus-stealing highlight for macOS.
//
// The ring follows the cursor so a person on the other end (or an agent reading a screenshot) can see
// what is being pointed at. ⌃⌥H highlights, ⌃⌥D hands the mouse to the overlay for arrows and notes,
// ⌃⌥R records the screen. Everything lives in a menu-bar popover.

// MARK: - state

final class AppModel: ObservableObject {
    @Published var highlightOn = false { didSet { save("highlight", highlightOn); changed() } }
    @Published var drawMode = false { didSet { save("draw", drawMode); changed() } }
    @Published var spotlight = false { didSet { save("spotlight", spotlight); changed() } }
    @Published var toolName = "arrow" { didSet { save("tool", toolName); changed() } }
    @Published var colorIndex = 0 { didSet { save("color", colorIndex); changed() } }
    @Published var lineWidth = 4.0 { didSet { save("width", lineWidth); changed() } }
    @Published var recording = false
    @Published var elapsed = 0.0
    @Published var preparingReview = false
    @Published var sessionStatus = "Record a walkthrough, mark it, then send it to your agent."
    @Published var autoReview = UserDefaults.standard.object(forKey: "sp.autoReview") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoReview, forKey: "sp.autoReview") }
    }
    @Published var lastSession: URL?
    @Published var reviewing = false
    @Published var lastClip: String?
    @Published var pointStatus = "Point at something and press ⌃⌥P"
    @Published var capturingPoint = false
    @Published var lastPoint: URL?

    var changed: () -> Void = {}

    static let colors: [(String, NSColor)] = [
        ("Yellow", .systemYellow), ("Red", .systemRed),
        ("Green", .systemGreen), ("Blue", .systemBlue),
    ]
    var color: NSColor { Self.colors[max(0, min(colorIndex, Self.colors.count - 1))].1 }

    init() {
        let d = UserDefaults.standard
        highlightOn = d.bool(forKey: "sp.highlight")
        drawMode = false // Never intercept clicks automatically on launch.
        spotlight = d.object(forKey: "sp.spotlight") as? Bool ?? false
        toolName = d.string(forKey: "sp.tool") ?? "arrow"
        colorIndex = d.integer(forKey: "sp.color")
        lineWidth = d.object(forKey: "sp.width") as? Double ?? 4
    }

    private func save(_ key: String, _ value: Any) { UserDefaults.standard.set(value, forKey: "sp." + key) }
}

// MARK: - overlay

final class HighlightView: NSView {
    struct Shape {
        enum Kind: String { case pen, arrow, rect, highlight }
        var kind: Kind
        var points: [CGPoint]
        var color: NSColor
        var width: Double
    }

    weak var model: AppModel?
    var shapes: [Shape] = []
    var labels: [(CGPoint, String)] = []
    var onAnnotation: ((String) -> Void)?
    private var current: Shape?

    override var isOpaque: Bool { false }

    private var mouse: CGPoint {
        guard let window else { return .zero }
        return convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let model else { return }

        if model.spotlight {
            let hole = 76.0
            let path = CGMutablePath()
            path.addRect(bounds)
            path.addRoundedRect(in: CGRect(x: mouse.x - hole, y: mouse.y - hole, width: hole * 2, height: hole * 2),
                                cornerWidth: 22, cornerHeight: 22)
            ctx.addPath(path)
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            ctx.fillPath(using: .evenOdd)
        }

        for shape in shapes { stroke(shape, in: ctx) }
        if let current { stroke(current, in: ctx) }

        for (point, text) in labels {
            let width = min(320.0, max(100.0, bounds.width - point.x - 20))
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: NSColor.black]
            let value = NSAttributedString(string: text, attributes: attributes)
            let measured = value.boundingRect(with: CGSize(width: width - 24, height: 200), options: [.usesLineFragmentOrigin])
            let rect = CGRect(x: min(max(8, point.x + 20), bounds.width - width - 8), y: max(8, min(point.y - measured.height - 24, bounds.height - measured.height - 32)), width: width, height: min(220, measured.height + 24))
            NSColor.systemYellow.withAlphaComponent(0.96).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
            value.draw(with: rect.insetBy(dx: 12, dy: 12), options: [.usesLineFragmentOrigin])
        }
        guard model.highlightOn || model.drawMode else { return }
        let p = mouse
        let ring = CGRect(x: p.x - 44, y: p.y - 44, width: 88, height: 88)
        ctx.setStrokeColor(model.color.withAlphaComponent(0.95).cgColor)
        ctx.setLineWidth(4)
        ctx.strokeEllipse(in: ring)
        ctx.setStrokeColor(model.color.withAlphaComponent(0.30).cgColor)
        ctx.setLineWidth(12)
        ctx.strokeEllipse(in: ring.insetBy(dx: -6, dy: -6))
    }

    func clearShapes() { shapes.removeAll(); labels.removeAll(); current = nil; needsDisplay = true }
    func undo() { if !shapes.isEmpty { shapes.removeLast(); needsDisplay = true } }

    private func stroke(_ shape: Shape, in ctx: CGContext) {
        guard let first = shape.points.first else { return }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        switch shape.kind {
        case .pen, .highlight:
            let path = CGMutablePath()
            path.move(to: first)
            for p in shape.points.dropFirst() { path.addLine(to: p) }
            ctx.addPath(path)
            ctx.setStrokeColor(shape.color.withAlphaComponent(shape.kind == .highlight ? 0.45 : 1).cgColor)
            ctx.setLineWidth(shape.kind == .highlight ? shape.width * 6 : shape.width)
            ctx.strokePath()
        case .rect:
            guard let last = shape.points.last else { return }
            let r = CGRect(x: min(first.x, last.x), y: min(first.y, last.y),
                           width: abs(last.x - first.x), height: abs(last.y - first.y))
            ctx.setStrokeColor(shape.color.cgColor)
            ctx.setLineWidth(shape.width)
            ctx.stroke(r)
        case .arrow:
            guard let last = shape.points.last else { return }
            ctx.setStrokeColor(shape.color.cgColor)
            ctx.setLineWidth(shape.width)
            ctx.move(to: first); ctx.addLine(to: last); ctx.strokePath()
            let angle = atan2(last.y - first.y, last.x - first.x)
            let head = 10.0 + shape.width * 3
            for side in [angle + .pi * 0.85, angle - .pi * 0.85] {
                ctx.move(to: last)
                ctx.addLine(to: CGPoint(x: last.x + cos(side) * head, y: last.y + sin(side) * head))
            }
            ctx.strokePath()
        }
    }

    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func mouseDown(with event: NSEvent) {
        guard model?.drawMode == true else { return }
        let kind = Shape.Kind(rawValue: model?.toolName ?? "arrow") ?? .arrow
        current = Shape(kind: kind, points: [point(event)], color: model?.color ?? .systemYellow,
                        width: model?.lineWidth ?? 4)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard model?.drawMode == true, var shape = current else { return }
        if shape.kind == .pen || shape.kind == .highlight { shape.points.append(point(event)) }
        else { shape.points = [shape.points[0], point(event)] }
        current = shape
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard model?.drawMode == true else { return }
        if let shape = current, shape.points.count > 1 {
            shapes.append(shape)
            onAnnotation?(shape.kind.rawValue)
        }
        current = nil
        // A completed stroke always restores normal clicks immediately.
        model?.drawMode = false
        needsDisplay = true
    }

    override func resetCursorRects() {
        if model?.drawMode == true { addCursorRect(bounds, cursor: .crosshair) }
    }
}

final class PointerWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - popover

struct MenuView: View {
    @ObservedObject var model: AppModel
    let onNote: () -> Void
    let onReview: () -> Void
    let onCopyReview: () -> Void
    let onCapture: () -> Void
    let onCopyPoint: () -> Void
    let onQuit: () -> Void
    let onOpenClip: () -> Void
    let onClear: () -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Screen Pointer").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(statusText).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }

            HStack {
                Button(model.recording ? "Stop recording" : "Record walkthrough") {
                    NotificationCenter.default.post(name: model.recording ? .stopRecording : .startRecording, object: nil)
                }.disabled(model.preparingReview)
                if model.recording { Text(time(model.elapsed)).monospacedDigit().foregroundStyle(.secondary) }
            }.buttonStyle(.borderedProminent)
            Text(model.sessionStatus).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(model.drawMode ? "Draw one mark. Normal clicks resume after the stroke." : "Normal clicks pass through. Switch windows and work as usual.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Add note", action: onNote).disabled(!model.recording)
                if model.lastClip != nil { Button("Show recording", action: onOpenClip) }
            }
            if model.lastSession != nil {
                HStack {
                    Button("Copy review prompt", action: onCopyReview)
                    Button("Review in OpenCode", action: onReview).disabled(model.reviewing || model.preparingReview || model.recording)
                }
            }
            Toggle("Review in OpenCode after stopping", isOn: $model.autoReview).font(.system(size: 11))
            Divider()
            Text("Show your agent a specific spot").font(.system(size: 12, weight: .semibold))
            Text("Point with your mouse, press ⌃⌥P, then ask your agent to look at your latest point.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                Button("Capture in 3 seconds", action: onCapture).disabled(model.capturingPoint)
                if model.lastPoint != nil { Button("Copy agent prompt", action: onCopyPoint) }
            }
            Text(model.pointStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Toggle(isOn: $model.highlightOn) { Label("Highlight cursor", systemImage: "circle.dashed") }
                .toggleStyle(.switch)
            Toggle(isOn: $model.spotlight) { Label("Dim the rest", systemImage: "spotlight") }
                .toggleStyle(.switch)

            Divider()

            Text("Annotate").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Toggle(isOn: $model.drawMode) { Label("Draw over the screen", systemImage: "pencil.tip") }
                .toggleStyle(.switch)
            Picker("Tool", selection: $model.toolName) {
                Label("Arrow", systemImage: "arrow.up.right").tag("arrow")
                Label("Pen", systemImage: "scribble").tag("pen")
                Label("Highlight", systemImage: "highlighter").tag("highlight")
                Label("Box", systemImage: "rectangle").tag("rect")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 8) {
                ForEach(Array(AppModel.colors.enumerated()), id: \.offset) { i, c in
                    Circle()
                        .fill(Color(nsColor: c.1))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.primary.opacity(model.colorIndex == i ? 0.55 : 0), lineWidth: 2))
                        .onTapGesture { model.colorIndex = i }
                }
                Spacer()
                Slider(value: $model.lineWidth, in: 2...12).frame(width: 90)
            }
            HStack {
                Button("Undo", action: onUndo)
                Button("Clear", action: onClear)
                Spacer()
            }
            .buttonStyle(.link)

            Divider()

            Text("⌃⌥R record · ⌃⌥D draw one mark · ⌃⌥N note")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
            Divider()
            HStack { Spacer(); Button("Quit", action: onQuit) }
        }
        .padding(16)
        .frame(width: 360)
    }

    private var statusText: String {
        if model.recording { return "recording" }
        if model.drawMode { return "drawing" }
        return model.highlightOn ? "pointing" : "idle"
    }

    private func time(_ t: Double) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

extension Notification.Name {
    static let startRecording = Notification.Name("sp.startRecording")
    static let stopRecording = Notification.Name("sp.stopRecording")
}

// MARK: - app

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var windows: [PointerWindow] = []
    private var timer: Timer?
    private var recordTimer: Timer?
    private var status: NSStatusItem!
    private var panel: NSPanel!
    private var hotKey: EventHotKeyRef?
    private var recordKey: EventHotKeyRef?
    private var drawKey: EventHotKeyRef?
    private var pointKey: EventHotKeyRef?
    private var noteKey: EventHotKeyRef?
    private var clearKey: EventHotKeyRef?
    private var activeSession: RecordingSession?
    private var notePanel: NSPanel?
    private var reviewProcess: Process?
    private var recorder: Process?
    private var recordingURL: URL?
    private var recordStarted = Date()

    private static let clips: URL = {
        let dir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Screen Pointer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.autosaveName = "sp.status"
        status.button?.image = NSImage(systemSymbolName: "circle.dashed", accessibilityDescription: "Screen Pointer")
        status.button?.imagePosition = .imageOnly
        status.button?.target = self
        status.button?.action = #selector(togglePanel)

        let host = NSHostingController(rootView: MenuView(
            model: model,
            onNote: { [weak self] in self?.addNote() },
            onReview: { [weak self] in self?.reviewInOpenCode() },
            onCopyReview: { [weak self] in self?.copyReviewPrompt() },
            onCapture: { [weak self] in self?.capturePoint(after: 3) },
            onCopyPoint: { [weak self] in self?.copyPointPrompt() },
            onQuit: { NSApp.terminate(nil) },
            onOpenClip: { [weak self] in self?.openLastClip() },
            onClear: { [weak self] in self?.clearAnnotations() },
            onUndo: { [weak self] in self?.allViews { $0.undo() } }
        ))
        let panel = NSPanel(contentViewController: host)
        panel.title = "Screen Pointer"
        panel.styleMask = [.titled, .closable, .utilityWindow, .nonactivatingPanel]
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = panel

        model.changed = { [weak self] in self?.applyModel() }
        NotificationCenter.default.addObserver(self, selector: #selector(startRecording),
                                               name: .startRecording, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(stopRecording),
                                               name: .stopRecording, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)

        registerHotKeys()
        model.lastClip = try? String(contentsOf: Self.clips.appendingPathComponent("last-recording.txt"),
                                     encoding: .utf8)

        if let data = try? Data(contentsOf: RecordingSession.root.appendingPathComponent("latest.json")),
           let latest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           latest["state"] as? String == "ready", let id = latest["id"] as? String, UUID(uuidString: id) != nil {
            let folder = RecordingSession.root.appendingPathComponent(id)
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent("notes.md").path) {
                model.lastSession = folder
                model.sessionStatus = "Your latest saved walkthrough is ready to review."
            }
        }
        let env = ProcessInfo.processInfo.environment
        if env["PTR_ON"] == "1" { model.highlightOn = true }
        if env["PTR_DRAW"] == "1" { model.drawMode = true }
        if env["PTR_POPOVER"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.showPanel() }
        }
        if let secs = Double(env["PTR_REC_SECONDS"] ?? "") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.startRecording()
                DispatchQueue.main.asyncAfter(deadline: .now() + secs) { self.stopRecording() }
            }
        }
        applyModel()
        DispatchQueue.main.async { [weak self] in self?.showPanel() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.recording { stopRecording(); return .terminateCancel }
        if model.preparingReview || model.reviewing { return .terminateCancel }
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    // MARK: state -> UI

    private func applyModel() {
        if model.highlightOn || model.drawMode || model.recording || windows.contains(where: { (($0.contentView as? HighlightView)?.shapes.isEmpty == false) || (($0.contentView as? HighlightView)?.labels.isEmpty == false) }) { showWindows() } else { hideWindows() }
        windows.forEach { w in
            w.ignoresMouseEvents = !model.drawMode
            w.contentView?.needsDisplay = true
            w.invalidateCursorRects(for: w.contentView!)
        }
        status.button?.image = NSImage(
            systemSymbolName: model.recording ? "record.circle.fill"
                : model.drawMode ? "pencil.tip"
                : model.highlightOn ? "circle.dashed.inset.filled" : "circle.dashed",
            accessibilityDescription: "Screen Pointer")
        status.button?.appearsDisabled = !(model.highlightOn || model.drawMode || model.recording)
    }

    @objc private func togglePanel() {
        if panel.isVisible { panel.orderOut(nil) } else { showPanel() }
    }

    private func showPanel() {
        guard let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let f = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: f.maxX - size.width - 20, y: f.maxY - size.height - 12))
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showWindows() {
        guard windows.isEmpty else { return }
        for screen in NSScreen.screens {
            let w = PointerWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = .floating
            w.backgroundColor = .clear
            w.isOpaque = false
            w.hasShadow = false
            w.ignoresMouseEvents = !model.drawMode
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let v = HighlightView(frame: screen.frame)
            v.model = model
            v.onAnnotation = { [weak self] kind in self?.activeSession?.add(kind: "annotation", text: kind, point: NSEvent.mouseLocation) }
            w.contentView = v
            w.orderFrontRegardless()
            windows.append(w)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.windows.forEach { $0.contentView?.needsDisplay = true }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func hideWindows() {
        timer?.invalidate(); timer = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func allViews(_ body: (HighlightView) -> Void) {
        windows.compactMap { $0.contentView as? HighlightView }.forEach(body)
    }

    @objc private func screensChanged() {
        guard !windows.isEmpty else { return }
        hideWindows(); showWindows()
    }

    // MARK: hotkeys

    private func registerHotKeys() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                switch hk.id {
                case 2: delegate.startRecording()          // ⌃⌥R (toggles in its own handler)
                case 3: delegate.toggleDraw()
                case 4: delegate.capturePoint(after: 0)
                case 5: delegate.addNote()
                case 6: delegate.clearAnnotations()
                default: delegate.toggleHighlight()
                }
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)

        let sig = OSType(0x50545231)  // 'PTR1'
        RegisterEventHotKey(UInt32(kVK_ANSI_H), UInt32(controlKey | optionKey),
                            EventHotKeyID(signature: sig, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(controlKey | optionKey),
                            EventHotKeyID(signature: sig, id: 2), GetApplicationEventTarget(), 0, &recordKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey),
                            EventHotKeyID(signature: sig, id: 3), GetApplicationEventTarget(), 0, &drawKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(controlKey | optionKey),
                            EventHotKeyID(signature: sig, id: 4), GetApplicationEventTarget(), 0, &pointKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey), EventHotKeyID(signature: sig, id: 5), GetApplicationEventTarget(), 0, &noteKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_C), UInt32(controlKey | optionKey), EventHotKeyID(signature: sig, id: 6), GetApplicationEventTarget(), 0, &clearKey)
    }

    private func toggleHighlight() {
        model.highlightOn.toggle()
    }

    private func toggleDraw() {
        model.drawMode.toggle()
        if model.drawMode { model.highlightOn = true }
    }

    // MARK: point for agent

    private func capturePoint(after delay: Double) {
        guard !model.capturingPoint else { return }
        guard #available(macOS 14.0, *) else {
            model.pointStatus = "Point capture requires macOS 14 or later."; return
        }
        model.capturingPoint = true
        model.pointStatus = delay > 0 ? "Move your mouse to the spot — capturing in 3 seconds…" : "Capturing…"
        panel.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.model.capturingPoint = false }
                do {
                    self.model.lastPoint = try await PointCapture.capture()
                    self.model.pointStatus = "Point saved. Ask your agent to read your latest point."
                    self.status.button?.toolTip = "Point saved — ⌃⌥P captures another spot"
                } catch {
                    let code = (error as NSError).code
                    self.model.pointStatus = code == -3801
                        ? "Screen Recording permission is required. Enable Screen Pointer in System Settings, then try again."
                        : "Capture failed (code \(code)). Check Screen Recording permission and try again."
                    self.showPanel()
                }
            }
        }
    }

    private func copyPointPrompt() {
        guard let url = model.lastPoint else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Look at my latest Screen Pointer capture using the latest_point MCP tool. The yellow marker is the spot I mean. If the tool is unavailable, inspect the local image at " + url.path + ". Tell me what is at that spot before making changes.", forType: .string)
        model.pointStatus = "Agent prompt copied. Paste it into your coding agent."
    }

    // MARK: recording

    @objc func startRecording() {
        if recorder != nil { stopRecording(); return }
        guard !model.preparingReview else { return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            model.sessionStatus = "Enable Screen Recording for Screen Pointer in System Settings, then try again."
            showPanel(); return
        }
        let mouse = NSEvent.mouseLocation
        let screens = NSScreen.screens
        guard let index = screens.firstIndex(where: { NSMouseInRect(mouse, $0.frame, false) }) else { return }
        do {
            let session = try RecordingSession(screen: screens[index], index: index + 1)
            activeSession = session
            model.drawMode = false
            allViews { $0.clearShapes() }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-v", "-x", "-D", String(index + 1), session.movie.path]
            p.terminationHandler = { [weak self] process in
                DispatchQueue.main.async { self?.finishedRecording(exitCode: process.terminationStatus) }
            }
            try p.run()
            recorder = p
            recordingURL = session.movie
            recordStarted = session.started
            model.recording = true
            model.elapsed = 0
            model.sessionStatus = "Recording display \(index + 1). Click freely; ⌃⌥D marks, ⌃⌥N adds a note."
            panel.orderOut(nil)
            recordTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.model.elapsed = Date().timeIntervalSince(self.recordStarted)
            }
            RunLoop.main.add(recordTimer!, forMode: .common)
            applyModel()
        } catch {
            activeSession?.fail(); activeSession = nil
            model.sessionStatus = "Recording could not start. Check permissions and available disk space."
            showPanel()
        }
    }

    @objc func stopRecording() {
        guard let recorder else { return }
        model.sessionStatus = "Finishing recording…"
        model.drawMode = false
        recorder.interrupt()
    }

    private func finishedRecording(exitCode: Int32) {
        recordTimer?.invalidate(); recordTimer = nil; recorder = nil
        model.recording = false; model.preparingReview = true
        model.sessionStatus = "Preparing timestamped notes and review frames…"
        notePanel?.close(); notePanel = nil
        applyModel(); showPanel()
        guard let session = activeSession else { model.preparingReview = false; return }
        activeSession = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.model.preparingReview = false }
            do {
                try await session.finish(exitCode: exitCode)
                self.model.lastClip = session.movie.path
                self.model.lastSession = session.directory
                try session.movie.path.write(to: Self.clips.appendingPathComponent("last-recording.txt"), atomically: true, encoding: .utf8)
                self.model.sessionStatus = "Ready: \(session.frames.count) review frames, \(session.events.count) notes and marks."
                if self.model.autoReview { self.reviewInOpenCode() }
            } catch {
                self.model.sessionStatus = "Recording was not usable. No review was sent. Check Screen Recording permission and try again."
            }
        }
    }

    private func clearAnnotations() {
        allViews { $0.clearShapes() }
        activeSession?.add(kind: "clear", text: "Cleared the on-screen annotations")
        model.drawMode = false
        applyModel()
    }

    private func addNote() {
        guard model.recording, notePanel == nil else { return }
        let point = NSEvent.mouseLocation
        let previous = NSWorkspace.shared.frontmostApplication
        model.drawMode = false
        let editor = NoteEditor(save: { [weak self] text in
            guard let self else { return }
            self.activeSession?.add(kind: "note", text: text, point: point)
            self.allViews { view in
                if let screen = view.window?.screen, NSMouseInRect(point, screen.frame, false) {
                    view.labels.append((CGPoint(x: point.x - screen.frame.minX, y: point.y - screen.frame.minY), String(text.prefix(250))))
                    view.needsDisplay = true
                }
            }
            self.notePanel?.close(); self.notePanel = nil
            previous?.activate(options: [])
        }, cancel: { [weak self] in
            self?.notePanel?.close(); self?.notePanel = nil
            previous?.activate(options: [])
        })
        let note = NSPanel(contentViewController: NSHostingController(rootView: editor))
        note.title = "Note for your agent"; note.styleMask = [.titled, .utilityWindow]
        note.isReleasedWhenClosed = false; note.level = .floating
        note.center(); note.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        notePanel = note
    }

    private func copyReviewPrompt() {
        guard let session = model.lastSession else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Review my Screen Pointer recording using latest_recording. Read the timestamped notes and inspect the frames. Tell me what you understood, what you suggest, and any uncertainties before making changes. Local session: " + session.path, forType: .string)
        model.sessionStatus = "Review prompt copied. Paste it into your connected coding agent."
    }

    private func reviewInOpenCode() {
        guard let session = model.lastSession, !model.reviewing else { return }
        guard let script = Bundle.main.url(forResource: "send_review", withExtension: "py") else {
            model.sessionStatus = "Review helper missing. Rebuild the app or use Copy review prompt."; return
        }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3", script.path, session.path]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = NSHomeDirectory() + "/.opencode/bin:" + NSHomeDirectory() + "/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        p.environment = env
        let log = session.appendingPathComponent("handoff.log")
        FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try? FileHandle(forWritingTo: log)
        p.standardOutput = handle; p.standardError = handle
        p.terminationHandler = { [weak self] proc in DispatchQueue.main.async {
            self?.model.reviewing = false; self?.reviewProcess = nil
            self?.model.sessionStatus = proc.terminationStatus == 0
                ? "Review finished in OpenCode. Open its Screen Pointer review session."
                : "OpenCode review did not finish. Your recording is saved; use Copy review prompt or check handoff.log."
            try? handle?.close()
        } }
        do { try p.run(); reviewProcess = p; model.reviewing = true; model.sessionStatus = "OpenCode is reviewing the frames and notes…" }
        catch { model.sessionStatus = "OpenCode could not start. Install it or use Copy review prompt." }
    }

    private func openLastClip() {
        guard let path = model.lastClip else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
