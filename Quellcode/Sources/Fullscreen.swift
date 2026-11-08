import AppKit
import SwiftUI
import AVKit
import ImageIO

final class ViewerState: ObservableObject {
    @Published var items: [MediaItem]
    @Published var index: Int
    @Published var candidate: Int
    @Published var filmstrip = false
    @Published var info = false
    var current: MediaItem { items[index] }
    init(items: [MediaItem], index: Int) { self.items = items; self.index = index; candidate = index }
    func move(_ delta: Int) {
        if filmstrip { candidate = min(items.count - 1, max(0, candidate + delta)) }
        else { index = min(items.count - 1, max(0, index + delta)); candidate = index }
    }
    func showStrip() { candidate = index; filmstrip = true }
    func confirm() { if filmstrip { index = candidate; filmstrip = false } }
}

final class PresentationWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var onKey: ((NSEvent) -> Bool)?
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        super.sendEvent(event)
    }
}

final class VideoSurface: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        (layer as? AVPlayerLayer)?.videoGravity = .resizeAspect
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func makeBackingLayer() -> CALayer { AVPlayerLayer() }
    var player: AVPlayer? {
        get { (layer as? AVPlayerLayer)?.player }
        set { (layer as? AVPlayerLayer)?.player = newValue }
    }
}

final class ImageCanvas: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var pixelSize = CGSize(width: 1, height: 1)
    var message = ""
    var zoom: CGFloat = 1
    var offset = CGPoint.zero
    var detailNeeded: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    var fitScale: CGFloat { min(bounds.width / max(1, pixelSize.width), bounds.height / max(1, pixelSize.height)) }
    func reset() { zoom = 1; offset = .zero; needsDisplay = true }
    func setZoom(_ value: CGFloat) {
        zoom = min(64, max(0.05, value)); constrain(); needsDisplay = true
        if fitScale * zoom * (window?.backingScaleFactor ?? 2) * max(pixelSize.width, pixelSize.height) > 4096 { detailNeeded?() }
    }
    func originalSize() { setZoom(1 / max(0.0001, fitScale * (window?.backingScaleFactor ?? 2))) }
    private func constrain() {
        let w = pixelSize.width * fitScale * zoom, h = pixelSize.height * fitScale * zoom
        offset.x = min(max(0, (w - bounds.width) / 2), max(-max(0, (w - bounds.width) / 2), offset.x))
        offset.y = min(max(0, (h - bounds.height) / 2), max(-max(0, (h - bounds.height) / 2), offset.y))
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.12, alpha: 1).setFill(); bounds.fill()
        if let image {
            let size = CGSize(width: pixelSize.width * fitScale * zoom, height: pixelSize.height * fitScale * zoom)
            let rect = CGRect(x: bounds.midX - size.width / 2 + offset.x, y: bounds.midY - size.height / 2 + offset.y, width: size.width, height: size.height)
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else if !message.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor.white.withAlphaComponent(0.7)]
            let text = message as NSString; let size = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY), withAttributes: attributes)
        }
    }
    func pan(x: CGFloat, y: CGFloat) { offset.x += x; offset.y += y; constrain(); needsDisplay = true }
    override func scrollWheel(with event: NSEvent) { pan(x: event.scrollingDeltaX, y: event.scrollingDeltaY) }
    override func rightMouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func rightMouseDragged(with event: NSEvent) { pan(x: event.deltaX, y: -event.deltaY) }
    override func rightMouseUp(with event: NSEvent) {}
    override func magnify(with event: NSEvent) { setZoom(zoom * (1 + event.magnification)) }
    override func mouseDragged(with event: NSEvent) { pan(x: event.deltaX, y: -event.deltaY) }
    override func mouseDown(with event: NSEvent) { if event.clickCount == 2 { if abs(zoom - 1) < 0.01 { originalSize() } else { reset() } } }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); constrain(); needsDisplay = true }
}

final class PresentationRoot: NSView {
    let canvas: ImageCanvas
    var reservedTop: CGFloat = 0 { didSet { resizeCanvas() } }
    init(canvas: ImageCanvas) { self.canvas = canvas; super.init(frame: .zero); wantsLayer = true; layer?.backgroundColor = NSColor.black.cgColor; addSubview(canvas) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); resizeCanvas() }
    func resizeCanvas() { canvas.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - reservedTop)) }
}

final class FullscreenController: NSObject {
    let model: AppModel
    let state: ViewerState
    let window: PresentationWindow
    let canvas = ImageCanvas()
    let movie = VideoSurface(frame: .zero)
    var player: AVPlayer?
    var playerObservation: NSKeyValueObservation?
    var infoView: NSHostingView<InfoPanel>?
    var stripView: NSHostingView<Filmstrip>?
    let linked: Bool
    private var synchronizing = false
    var onClose: (() -> Void)?
    private var decodeQueue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 1; q.qualityOfService = .userInitiated; return q }()
    private var token = UUID()
    private var detailRequested = false
    private var showOriginal = false
    private var closed = false
    private var observers: [NSObjectProtocol] = []

    init(model: AppModel, item: MediaItem, screen: NSScreen, linked: Bool = false) {
        self.model = model; self.linked = linked
        state = ViewerState(items: model.displayMediaItems, index: model.displayMediaItems.firstIndex(where: { $0.id == item.id }) ?? 0)
        window = PresentationWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        window.title = "Bild-Atelier · Vollbild"
        window.setAccessibilityRole(.window)
        window.setAccessibilitySubrole(.standardWindow)
        window.isReleasedWhenClosed = false; window.backgroundColor = .black
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        window.collectionBehavior = [.fullScreenAuxiliary, .stationary]
        window.hidesOnDeactivate = false
        window.setFrame(screen.frame, display: false)
        let root = PresentationRoot(canvas: canvas)
        root.frame = CGRect(origin: .zero, size: screen.frame.size)
        root.reservedTop = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
        window.contentView = root
        movie.frame = canvas.bounds; movie.autoresizingMask = [.width, .height]
        movie.isHidden = true; canvas.addSubview(movie)
        window.onKey = { [weak self] in self?.handle($0) ?? false }
        canvas.detailNeeded = { [weak self] in self?.loadDetail() }
    }
    func show() {
        // A borderless window covers only its own screen. Never change process-wide presentation options.
        if linked { window.orderFront(nil) } else { window.makeKeyAndOrderFront(nil) }
        window.makeFirstResponder(canvas); showCurrent()
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, let screen = self.window.screen ?? NSScreen.main else { return }; self.window.setFrame(screen.frame, display: true); (self.window.contentView as? PresentationRoot)?.reservedTop = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness); self.layoutOverlays()
        })
    }
    func close() {
        guard !closed else { return }; closed = true; token = UUID(); decodeQueue.cancelAllOperations()
        observers.forEach(NotificationCenter.default.removeObserver); observers = []
        player?.pause(); movie.player = nil; player = nil; playerObservation = nil
        if !linked { model.selectedID = state.current.id }
        window.orderOut(nil); window.close(); onClose?()
    }
    @discardableResult func handle(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers?.lowercased() == "w" { close(); return true }
            return false
        }
        switch event.keyCode {
        case 53: close()
        case 123, 124:
            let old = state.index; state.move(event.keyCode == 123 ? -1 : 1)
            if state.index != old { showCurrent() }
        case 126: state.showStrip(); updateStrip()
        case 125, 36, 76:
            if state.filmstrip { let old = state.index; state.confirm(); updateStrip(); if old != state.index { showCurrent() } }
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "i": state.info.toggle(); updateInfo()
            case "o": if !state.current.video { showOriginal.toggle(); showCurrent() }
            case "+", "=": if !state.current.video { canvas.setZoom(canvas.zoom * 1.25) }
            case "-", "−": if !state.current.video { canvas.setZoom(canvas.zoom / 1.25) }
            case "0": canvas.reset()
            case "1": canvas.originalSize()
            case " ": if let player { if player.rate == 0 { if let item = player.currentItem, CMTimeCompare(item.currentTime(), item.duration) >= 0 { player.seek(to: .zero) }; player.play() } else { player.pause() } }
            default: return false
            }
        }; NSCursor.setHiddenUntilMouseMoves(true); return true
    }
    func followSelection() {
        guard linked, !closed, !synchronizing, let item = model.selected, !item.isDirectory, item.id != state.current.id else { return }
        synchronizing = true; defer { synchronizing = false }
        state.items = model.displayMediaItems
        state.index = state.items.firstIndex(where: { $0.id == item.id }) ?? 0
        state.candidate = state.index; state.filmstrip = false; updateStrip(); showCurrent()
    }
    func showCurrent() {
        let item = state.current
        model.requestMetadata(item)
        if model.selectedID != item.id { synchronizing = true; model.selectedID = item.id; synchronizing = false }
        canvas.setAccessibilityElement(true)
        canvas.setAccessibilityRole(.image)
        canvas.setAccessibilityLabel(item.url.lastPathComponent)
        token = UUID(); let currentToken = token; detailRequested = false
        decodeQueue.cancelAllOperations(); player?.pause(); player = nil; movie.player = nil; playerObservation = nil
        let preview = showOriginal ? nil : ThumbnailStore.shared.cached(item)
        canvas.pixelSize = preview?.size ?? CGSize(width: 1, height: 1)
        canvas.image = preview; canvas.message = "Wird geladen …"; canvas.reset(); movie.isHidden = !item.video
        if item.video {
            canvas.message = ""; player = AVPlayer(url: item.url); movie.player = player
            playerObservation = player?.currentItem?.observe(\.status, options: [.new]) { [weak self] playerItem, _ in
                DispatchQueue.main.async {
                    guard let self, self.token == currentToken else { return }
                    if playerItem.status == .failed { self.movie.isHidden = true; self.canvas.message = "Dieses Video kann macOS nicht wiedergeben."; self.canvas.needsDisplay = true }
                }
            }
            player?.play()
        } else {
            let original = showOriginal
            decodeQueue.addOperation { [weak self] in
                let rendered = autoreleasepool { ImageRenderer.render(item, maxPixel: 4096, original: original) }
                let image = rendered?.image, size = rendered?.pixelSize ?? CGSize(width: 1, height: 1)
                DispatchQueue.main.async {
                    guard let self, !self.closed, self.token == currentToken else { return }
                    item.renderWarning = rendered?.warning
                    self.canvas.pixelSize = size; self.canvas.image = image
                    self.canvas.message = image == nil ? "Dieses Bild kann macOS nicht lesen." : ""
                    self.canvas.needsDisplay = true
                }
            }
        }
        updateInfo(); window.makeFirstResponder(canvas)
    }
    private func loadDetail() {
        guard !detailRequested, !state.current.video, max(canvas.pixelSize.width, canvas.pixelSize.height) > 4096 else { return }
        detailRequested = true; let currentToken = token; let item = state.current; let original = showOriginal
        let maximum = Int(max(canvas.pixelSize.width, canvas.pixelSize.height))
        decodeQueue.addOperation { [weak self] in
            let image = autoreleasepool { ImageRenderer.render(item, maxPixel: maximumForDetail(item, fallback: maximum), original: original)?.image }
            DispatchQueue.main.async { guard let self, !self.closed, self.token == currentToken, let image else { return }; self.canvas.image = image }
        }
    }
    private func updateInfo() {
        infoView?.removeFromSuperview(); infoView = nil
        if state.info { let view = NSHostingView(rootView: InfoPanel(item: state.current, original: showOriginal)); canvas.addSubview(view); infoView = view }
        layoutOverlays()
    }
    private func updateStrip() {
        if state.filmstrip && stripView == nil {
            let view = NSHostingView(rootView: Filmstrip(state: state, choose: { [weak self] index in
                guard let self else { return }; self.state.candidate = index; self.state.confirm(); self.updateStrip(); self.showCurrent()
            }))
            canvas.addSubview(view); stripView = view
        } else if !state.filmstrip { stripView?.removeFromSuperview(); stripView = nil }
        layoutOverlays(); window.makeFirstResponder(canvas)
    }
    private func layoutOverlays() {
        let b = canvas.bounds
        infoView?.frame = CGRect(x: b.width * 2 / 3, y: state.filmstrip ? 168 : 0, width: b.width / 3, height: b.height - (state.filmstrip ? 168 : 0))
        infoView?.autoresizingMask = [.minXMargin, .height]
        stripView?.frame = CGRect(x: 0, y: 0, width: b.width, height: 168); stripView?.autoresizingMask = [.width, .maxYMargin]
    }
}

private func maximumForDetail(_ item: MediaItem, fallback: Int) -> Int {
    guard let ref = item.sidecar, let size = XMPDocument.read(ref).originalSize else { return fallback }
    return Int(max(size.width, size.height))
}

struct InfoPanel: View {
    @ObservedObject var item: MediaItem
    var original = false
    private let groups: [(String, [MetaField])] = [
        ("XMP", [.rating, .colorLabel, .nitroFlag, .xmpStatus]),
        ("DATEI", [.kind, .size, .dimensions, .duration, .colorSpace]),
        ("AUFNAHME", [.taken, .camera, .lens, .aperture, .shutter, .iso, .focalLength, .exposureBias, .flash, .gps]),
        ("IPTC", [.title, .caption, .keywords, .creator, .copyright, .city, .region, .country, .credit, .source])
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text(item.url.lastPathComponent).font(.system(size: 19, weight: .semibold)).textSelection(.enabled)
                Text("i · Informationen ausblenden").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                if item.sidecar != nil { Text(original ? "Original · O: XMP-Vorschau" : "XMP-Vorschau · O: Original").font(.caption) }
                if let warning = item.renderWarning { Text(warning).font(.caption).foregroundStyle(.orange) }
                if !item.metadataLoaded { Text("Metadaten werden gelesen …").font(.caption).foregroundStyle(.white.opacity(0.6)) }
                ForEach(groups, id: \.0) { title, fields in
                    if fields.contains(where: { item.value($0) != "—" }) {
                        Text(title).font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(.white.opacity(0.45)).padding(.top, 12)
                        ForEach(fields.filter { item.value($0) != "—" }) { field in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(field.label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                                Text(item.value(field)).font(.system(size: 13)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(28)
        }.foregroundStyle(.white).background(Color.black.opacity(0.76)).environment(\.colorScheme, .dark)
    }
}

struct Filmstrip: View {
    @ObservedObject var state: ViewerState
    var choose: (Int) -> Void
    var body: some View {
        VStack(spacing: 8) {
            HStack { Text("← →  Vorschau wählen     ↓  Anzeigen"); Spacer(); Text("\(state.candidate + 1) / \(state.items.count)") }.font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).padding(.horizontal, 22).padding(.top, 12)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                            VStack(spacing: 4) {
                                ThumbnailView(item: item).frame(width: 120, height: 83).clipShape(RoundedRectangle(cornerRadius: 4)).padding(3)
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(state.candidate == index ? Color.accentColor : .clear, lineWidth: 3))
                                Text(item.url.lastPathComponent).font(.system(size: 10)).foregroundStyle(.white.opacity(state.candidate == index ? 1 : 0.55)).lineLimit(1).frame(width: 120)
                            }.id(index).onTapGesture { choose(index) }
                        }
                    }.padding(.horizontal, 22)
                }.onChange(of: state.candidate) { index in proxy.scrollTo(index, anchor: .center) }.onAppear { proxy.scrollTo(state.candidate, anchor: .center) }
            }
            Spacer(minLength: 8)
        }.background(Color.black.opacity(0.88)).environment(\.colorScheme, .dark)
    }
}
