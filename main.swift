// Minuteur visuel pour macOS : disque seul, sens horaire, sans chiffres, toujours au premier plan.
// Clic = démarrer / pause. Clic maintenu + glisser = déplacer. Clic droit = réglages.
import Cocoa
import ServiceManagement

let cmToPt: CGFloat = 72.0 / 2.54
let prefs = UserDefaults.standard
let defaultColors: [String: String] = ["main": "#2f9e44", "mid": "#1971c2", "fin": "#f08c00"]
let palette: [(String, String)] = [
    ("Vert", "#2f9e44"), ("Bleu", "#1971c2"), ("Violet", "#7048e8"), ("Jaune", "#f2c200"),
    ("Orange", "#f08c00"), ("Rouge", "#e03131"), ("Gris", "#495057")
]

extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count != 6 { s = "000000" }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(srgbRed: CGFloat((v >> 16) & 0xff) / 255.0,
                  green: CGFloat((v >> 8) & 0xff) / 255.0,
                  blue: CGFloat(v & 0xff) / 255.0,
                  alpha: 1.0)
    }
    var hexString: String {
        let c = self.usingColorSpace(.sRGB) ?? self
        let r = UInt32(max(0, min(255, (c.redComponent * 255).rounded())))
        let g = UInt32(max(0, min(255, (c.greenComponent * 255).rounded())))
        let b = UInt32(max(0, min(255, (c.blueComponent * 255).rounded())))
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}

func hexFor(_ key: String) -> String {
    return prefs.string(forKey: key) ?? defaultColors[key] ?? "#2f9e44"
}

func isOn(_ key: String) -> Bool {
    let k = key + "On"
    if prefs.object(forKey: k) == nil { return true }
    return prefs.bool(forKey: k)
}

final class TimerView: NSView {
    var D: CGFloat = 108
    var strip: CGFloat = 23
    var total: Double = 25 * 60
    var remaining: Double = 25 * 60
    var running = false
    var lastTick = Date()
    var hover = false
    var blink = false
    var pressing = false
    var moving = false
    var pressMouse = NSPoint.zero
    var winOrigin0 = NSPoint.zero
    var editingKey = "main"
    var timer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        loadSettings()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) non utilisé")
    }

    override var isFlipped: Bool { return true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }

    // MARK: réglages

    func loadSettings() {
        let cm = prefs.double(forKey: "sizeCm")
        let size = cm == 0 ? 3.8 : cm
        D = CGFloat(size) * cmToPt
        strip = 0.8 * cmToPt
        let m = prefs.integer(forKey: "minutes")
        let minutes = m == 0 ? 25 : m
        total = Double(minutes) * 60
        remaining = total
    }

    func currentColor() -> NSColor {
        let m = remaining / 60
        if isOn("fin") && m > 0 && m <= 5 { return NSColor(hex: hexFor("fin")) }
        if isOn("mid") && m > 5 && m <= 10 { return NSColor(hex: hexFor("mid")) }
        return NSColor(hex: hexFor("main"))
    }

    func saveOrigin() {
        guard let w = window else { return }
        prefs.set(Double(w.frame.origin.x), forKey: "originX")
        prefs.set(Double(w.frame.origin.y), forKey: "originY")
    }

    // MARK: dessin

    func buttonCenter(_ i: Int) -> NSPoint {
        return NSPoint(x: D * CGFloat(i + 1) / 4.0, y: D + strip / 2)
    }

    func point(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ deg: Double) -> NSPoint {
        let a = deg * Double.pi / 180.0
        return NSPoint(x: cx + r * CGFloat(sin(a)), y: cy - r * CGFloat(cos(a)))
    }

    override func draw(_ dirtyRect: NSRect) {
        let cx = D / 2
        let cy = D / 2
        let Rf = D / 2 - 2
        let rd = Rf - D * 0.07

        let facePath = NSBezierPath(ovalIn: NSRect(x: cx - Rf, y: cy - Rf, width: 2 * Rf, height: 2 * Rf))
        (blink ? NSColor(hex: hexFor("fin")) : NSColor.white).setFill()
        facePath.fill()
        NSColor(white: 0.72, alpha: 1).setStroke()
        facePath.lineWidth = 1
        facePath.stroke()

        let small = NSBezierPath()
        let big = NSBezierPath()
        for i in 0..<60 {
            let deg = Double(i) * 6.0
            let isBig = i % 5 == 0
            let r1 = rd + D * 0.012
            let r2 = rd + D * (isBig ? 0.05 : 0.035)
            let p = isBig ? big : small
            p.move(to: point(cx, cy, r1, deg))
            p.line(to: point(cx, cy, r2, deg))
        }
        NSColor(white: 0.6, alpha: 1).setStroke()
        small.lineWidth = 0.6
        small.stroke()
        big.lineWidth = 1.4
        big.stroke()

        let r = max(0.0, min(1.0, remaining / 3600.0))
        currentColor().setFill()
        if r >= 0.9999 {
            NSBezierPath(ovalIn: NSRect(x: cx - rd, y: cy - rd, width: 2 * rd, height: 2 * rd)).fill()
        } else if r > 0 {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: cx, y: cy))
            let start = 360.0 * (1.0 - r)
            p.line(to: point(cx, cy, rd, start))
            var a = start + 1.0
            while a < 360.0 {
                p.line(to: point(cx, cy, rd, a))
                a += 1.0
            }
            p.line(to: point(cx, cy, rd, 360.0))
            p.close()
            p.fill()
        }

        if hover && !moving {
            let rad = strip / 2 - 1
            let glyphs = ["\u{21BA}", "\u{2699}", "\u{2715}"]
            for i in 0..<3 {
                let c = buttonCenter(i)
                let circle = NSBezierPath(ovalIn: NSRect(x: c.x - rad, y: c.y - rad, width: 2 * rad, height: 2 * rad))
                NSColor.white.setFill()
                circle.fill()
                NSColor(white: 0.5, alpha: 1).setStroke()
                circle.lineWidth = 1
                circle.stroke()
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: rad * 1.1),
                    .foregroundColor: NSColor(white: 0.2, alpha: 1)
                ]
                let s = NSAttributedString(string: glyphs[i], attributes: attrs)
                let sz = s.size()
                s.draw(at: NSPoint(x: c.x - sz.width / 2, y: c.y - sz.height / 2))
            }
        }
    }

    // MARK: horloge

    func tick() {
        if running {
            let now = Date()
            remaining -= now.timeIntervalSince(lastTick)
            lastTick = now
            if remaining <= 0 {
                remaining = 0
                running = false
                flash(12)
            }
            needsDisplay = true
        }
    }

    func flash(_ n: Int) {
        if n == 0 {
            blink = false
            needsDisplay = true
            return
        }
        blink.toggle()
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.flash(n - 1)
        }
    }

    func toggle() {
        if running {
            running = false
        } else {
            if remaining <= 0 { remaining = total }
            running = true
            lastTick = Date()
        }
        needsDisplay = true
    }

    func resetTimer() {
        running = false
        remaining = total
        needsDisplay = true
    }

    func setMinutes(_ m: Int) {
        let v = max(1, min(60, m))
        prefs.set(v, forKey: "minutes")
        total = Double(v) * 60
        remaining = total
        lastTick = Date()
        needsDisplay = true
    }

    func applySize(_ cm: Double) {
        let v = max(2.0, min(10.0, cm))
        prefs.set(v, forKey: "sizeCm")
        D = CGFloat(v) * cmToPt
        strip = 0.8 * cmToPt
        guard let w = window else { return }
        let old = w.frame
        let newH = D + strip
        w.setFrame(NSRect(x: old.minX, y: old.maxY - newH, width: D, height: newH), display: true)
        needsDisplay = true
        saveOrigin()
    }

    func setColor(_ key: String, _ hex: String) {
        prefs.set(hex, forKey: key)
        if key != "main" { prefs.set(true, forKey: key + "On") }
        needsDisplay = true
    }

    // MARK: souris

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        hover = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hover = false
        needsDisplay = true
    }

    func hitButton(_ p: NSPoint) -> Int? {
        if p.y < D { return nil }
        let rad = strip / 2
        for i in 0..<3 {
            let c = buttonCenter(i)
            if hypot(p.x - c.x, p.y - c.y) <= rad { return i }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let b = hitButton(p) {
            if b == 0 {
                resetTimer()
            } else if b == 1 {
                NSMenu.popUpContextMenu(makeMenu(), with: event, for: self)
            } else {
                saveOrigin()
                NSApp.terminate(nil)
            }
            return
        }
        if hypot(p.x - D / 2, p.y - D / 2) <= D / 2 - 2 {
            pressing = true
            moving = false
            pressMouse = NSEvent.mouseLocation
            winOrigin0 = window?.frame.origin ?? NSPoint.zero
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if !pressing { return }
        let m = NSEvent.mouseLocation
        let dx = m.x - pressMouse.x
        let dy = m.y - pressMouse.y
        if !moving && hypot(dx, dy) > 5 { moving = true }
        if moving {
            window?.setFrameOrigin(NSPoint(x: winOrigin0.x + dx, y: winOrigin0.y + dy))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if pressing {
            if moving { saveOrigin() } else { toggle() }
        }
        pressing = false
        moving = false
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        NSMenu.popUpContextMenu(makeMenu(), with: event, for: self)
    }

    // MARK: menu

    func item(_ title: String, _ action: Selector, tag: Int = 0, rep: Any? = nil, on: Bool = false) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.target = self
        it.tag = tag
        it.representedObject = rep
        it.state = on ? .on : .off
        return it
    }

    func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.submenu = menu
        return it
    }

    func makeMenu() -> NSMenu {
        let m = NSMenu()

        let curMin = Int(total / 60)
        let dur = NSMenu()
        for mn in [5, 10, 15, 20, 25, 30, 45, 60] {
            dur.addItem(item("\(mn) min", #selector(pickMinutes(_:)), tag: mn, on: mn == curMin))
        }
        dur.addItem(NSMenuItem.separator())
        dur.addItem(item("Autre durée…", #selector(askMinutes)))
        m.addItem(submenu("Durée", dur))

        let curSize = prefs.double(forKey: "sizeCm") == 0 ? 3.8 : prefs.double(forKey: "sizeCm")
        let sizes = NSMenu()
        for t in [30, 35, 40, 50, 60, 80] {
            let v = Double(t) / 10.0
            let label = (v == v.rounded() ? String(Int(v)) : String(v).replacingOccurrences(of: ".", with: ",")) + " cm"
            sizes.addItem(item(label, #selector(pickSize(_:)), tag: t, on: abs(v - curSize) < 0.01))
        }
        sizes.addItem(NSMenuItem.separator())
        sizes.addItem(item("Autre taille…", #selector(askSize)))
        m.addItem(submenu("Taille", sizes))

        let kinds: [(String, String, Bool)] = [
            ("main", "Couleur du disque", false),
            ("mid", "Couleur entre 10 et 5 min avant la fin", true),
            ("fin", "Couleur des 5 dernières minutes", true)
        ]
        for (key, title, optional) in kinds {
            let sub = NSMenu()
            if optional {
                sub.addItem(item("Désactivée", #selector(disableColor(_:)), rep: key, on: !isOn(key)))
            }
            for (name, hex) in palette {
                let selected = hexFor(key).lowercased() == hex && (!optional || isOn(key))
                sub.addItem(item(name, #selector(pickColor(_:)), rep: key + "|" + hex, on: selected))
            }
            sub.addItem(NSMenuItem.separator())
            sub.addItem(item("Autre couleur…", #selector(otherColor(_:)), rep: key))
            m.addItem(submenu(title, sub))
        }

        m.addItem(NSMenuItem.separator())
        if #available(macOS 13.0, *) {
            let enabled = SMAppService.mainApp.status == .enabled
            m.addItem(item("Lancer au démarrage du Mac", #selector(toggleLogin(_:)), on: enabled))
        }
        m.addItem(item("Quitter", #selector(quitApp)))
        return m
    }

    @objc func pickMinutes(_ s: NSMenuItem) { setMinutes(s.tag) }

    @objc func askMinutes() {
        if let v = askNumber("Durée", "Durée en minutes (1 à 60) :", String(Int(total / 60))) {
            setMinutes(Int(v.rounded()))
        }
    }

    @objc func pickSize(_ s: NSMenuItem) { applySize(Double(s.tag) / 10.0) }

    @objc func askSize() {
        let cur = prefs.double(forKey: "sizeCm") == 0 ? 3.8 : prefs.double(forKey: "sizeCm")
        if let v = askNumber("Taille", "Diamètre du disque en cm (2 à 10) :", String(cur)) {
            applySize(v)
        }
    }

    @objc func pickColor(_ s: NSMenuItem) {
        guard let rep = s.representedObject as? String else { return }
        let parts = rep.components(separatedBy: "|")
        if parts.count == 2 { setColor(parts[0], parts[1]) }
    }

    @objc func disableColor(_ s: NSMenuItem) {
        guard let key = s.representedObject as? String else { return }
        prefs.set(false, forKey: key + "On")
        needsDisplay = true
    }

    @objc func otherColor(_ s: NSMenuItem) {
        guard let key = s.representedObject as? String else { return }
        editingKey = key
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSColorPanel.shared
        panel.color = NSColor(hex: hexFor(key))
        panel.setTarget(self)
        panel.setAction(#selector(panelChanged(_:)))
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc func panelChanged(_ sender: Any?) {
        if let p = sender as? NSColorPanel { setColor(editingKey, p.color.hexString) }
    }

    @objc func toggleLogin(_ s: NSMenuItem) {
        if #available(macOS 13.0, *) {
            let svc = SMAppService.mainApp
            do {
                if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
            } catch {
                NSApp.activate(ignoringOtherApps: true)
                let a = NSAlert()
                a.messageText = "Impossible de modifier le lancement au démarrage"
                a.informativeText = "Copiez d'abord l'application dans le dossier Applications, puis réessayez."
                a.runModal()
            }
        }
    }

    @objc func quitApp() {
        saveOrigin()
        NSApp.terminate(nil)
    }

    func askNumber(_ title: String, _ message: String, _ initial: String) -> Double? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Annuler")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            return Double(field.stringValue.replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var view: TimerView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }

        let v = TimerView(frame: NSRect(x: 0, y: 0, width: 108, height: 131))
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: v.D, height: v.D + v.strip),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = v
        w.isOpaque = false
        w.backgroundColor = NSColor.clear
        w.hasShadow = false
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        w.isReleasedWhenClosed = false
        w.hidesOnDeactivate = false

        let size = NSSize(width: v.D, height: v.D + v.strip)
        var origin: NSPoint? = nil
        if prefs.object(forKey: "originX") != nil {
            let o = NSPoint(x: prefs.double(forKey: "originX"), y: prefs.double(forKey: "originY"))
            let r = NSRect(origin: o, size: size)
            if NSScreen.screens.contains(where: { $0.frame.intersects(r) }) { origin = o }
        }
        if origin == nil {
            let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            origin = NSPoint(x: vf.maxX - size.width - 40, y: vf.minY + 80)
        }
        w.setFrame(NSRect(origin: origin!, size: size), display: true)
        w.orderFrontRegardless()
        window = w
        view = v
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { return false }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
