import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    var model = AppModel(restore: !CommandLine.arguments.contains("--demo"))
    var window: NSWindow!
    var settingsWindow: NSWindow?
    var viewer: FullscreenController?
    var keyMonitor: Any?
    var pendingURLs: [URL] = []
    var ready = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Bild-Atelier"; window.minSize = NSSize(width: 1060, height: 550)
        window.isReleasedWhenClosed = false; window.delegate = self
        window.contentView = NSHostingView(rootView: BrowserView(model: model, preferences: model.preferences))
        window.setFrameAutosaveName("BrowserWindow"); window.center(); window.makeKeyAndOrderFront(nil)
        model.openViewer = { [weak self] item in self?.open(item) }
        model.selectionChanged = { [weak self] in self?.viewer?.followSelection() }
        model.showSettings = { [weak self] in self?.settings() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, (self.viewer == nil || self.viewer?.linked == true), NSApp.keyWindow === self.window, event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return event }
            if let responder = self.window.firstResponder, responder is NSTextView { return event }
            if event.keyCode == 36 || event.keyCode == 49 { if let item = self.model.selected { self.open(item); return nil } }
            // NSTableView handles its own vertical selection; grid arrows follow the visual geometry.
            if !self.model.preferences.listMode, [123,124,125,126].contains(event.keyCode), !self.model.displayItems.isEmpty {
                let current = self.model.selectedID.flatMap { self.model.displayIndex[$0] } ?? 0
                let available = self.window.contentView?.bounds.width ?? 1000
                let browserWidth = available - (self.model.sidebarVisible ? 245 : 0) - 44
                let cols = max(1, Int((browserWidth + 18) / (self.model.preferences.thumbnailSize + 18)))
                let delta = event.keyCode == 123 ? -1 : event.keyCode == 124 ? 1 : event.keyCode == 125 ? cols : -cols
                self.model.select(self.model.displayItems[min(self.model.displayItems.count - 1, max(0, current + delta))], modifiers: event.modifierFlags); return nil
            }; return event
        }
        if let i = CommandLine.arguments.firstIndex(of: "--folder"), i + 1 < CommandLine.arguments.count { model.add([URL(fileURLWithPath: CommandLine.arguments[i + 1])]) }
        else if let id = Preferences.defaults.string(forKey: "lastFolder") { model.selectFolder(id) }
        ready = true
        if !pendingURLs.isEmpty { let urls = pendingURLs; pendingURLs = []; openURLs(urls) }
        NSApp.activate(ignoringOtherApps: true)
        // Optional developer fixture generation; absent from the release Info.plist.
        if let fixtureFolder = Bundle.main.object(forInfoDictionaryKey: "BildAtelierFixtureFolder") as? String {
            DispatchQueue.global(qos: .utility).async {
                let folder = URL(fileURLWithPath: fixtureFolder)
                do { try SelfTests.createMovie(folder.appendingPathComponent("09_Video.mp4")); try "Video fixture ready".write(to: folder.appendingPathComponent("video-test-result.txt"), atomically: true, encoding: .utf8) }
                catch { try? String(describing: error).write(to: folder.appendingPathComponent("video-test-result.txt"), atomically: true, encoding: .utf8) }
            }
        }
    }
    func open(_ item: MediaItem) {
        if item.isDirectory { model.navigate(to: item.url); return }
        guard let browserScreen = window.screen ?? NSScreen.main else { return }
        let requestedOther = NSApp.currentEvent?.modifierFlags.contains(.command) == true
        let other = NSScreen.screens.first { $0 !== browserScreen }
        let linked = requestedOther && other != nil
        if let viewer {
            if viewer.linked && !requestedOther { viewer.followSelection(); return }
            viewer.close()
        }
        let controller = FullscreenController(model: model, item: item, screen: linked ? other! : browserScreen, linked: linked); viewer = controller
        controller.onClose = { [weak self] in self?.viewer = nil; self?.window.makeKeyAndOrderFront(nil) }
        controller.show()
        if linked { window.makeKeyAndOrderFront(nil) }
    }
    func openURLs(_ urls: [URL]) {
        if let image = urls.first(where: { MediaItem.classify($0) != nil }) {
            viewer?.close()
            let target = image.resolvingSymlinksInPath().standardizedFileURL
            model.pendingOpenURL = target
            model.add([target.deletingLastPathComponent()])
        } else { model.add(urls) }
    }
    @objc func settings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 630,height: 490), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Bild-Atelier · Einstellungen"; w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(preferences: model.preferences)); w.center(); settingsWindow = w
        }; settingsWindow?.makeKeyAndOrderFront(nil)
    }
    private var editingText: Bool { NSApp.keyWindow?.firstResponder is NSTextView }
    private var browserActionsAvailable: Bool { NSApp.keyWindow === window && !model.fileOperationBusy && (viewer == nil || viewer?.linked == true) }
    @objc func copySelection() {
        if editingText { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) }
        else if browserActionsAvailable { model.copyFiles() }
    }
    @objc func cutSelection() {
        if editingText { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) }
        else if browserActionsAvailable { model.copyFiles(cut: true) }
    }
    @objc func pasteSelection() {
        if editingText { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) }
        else if browserActionsAvailable { model.pasteFiles() }
    }
    @objc func selectEverything() {
        if editingText { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) }
        else if browserActionsAvailable { model.selectAllFiles() }
    }
    @objc func moveSelectionHere() { if browserActionsAvailable && !editingText { model.pasteFiles(forceMove: true) } }
    @objc func duplicateSelection() { if browserActionsAvailable && !editingText { model.duplicateFiles() } }
    @objc func renameSelection() { if browserActionsAvailable && !editingText { model.renameFile() } }
    @objc func moveSelectionToFolder() { if browserActionsAvailable && !editingText { model.moveFilesToFolder() } }
    @objc func trashSelection() { if browserActionsAvailable && !editingText { model.trashFiles() } }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let action = menuItem.action
        let textActions: [Selector] = [#selector(copySelection), #selector(cutSelection), #selector(pasteSelection), #selector(selectEverything)]
        let fileActions: [Selector] = textActions + [#selector(moveSelectionHere), #selector(duplicateSelection), #selector(renameSelection), #selector(moveSelectionToFolder), #selector(trashSelection)]
        guard let action, fileActions.contains(action) else { return true }
        if editingText { return textActions.contains(action) }
        guard browserActionsAvailable else { return false }
        if action == #selector(pasteSelection) || action == #selector(moveSelectionHere) { return model.canPasteFiles }
        if action == #selector(selectEverything) { return !model.displayItems.isEmpty }
        if action == #selector(renameSelection) { return model.selectedItems.count == 1 }
        return !model.selectedItems.isEmpty
    }
    @objc func addFolder() { model.addFolders() }
    @objc func refresh() { model.refresh() }
    @objc func toggleSidebar() { model.sidebarVisible.toggle() }
    @objc func newGroup() { model.createGroup() }
    @objc func showBrowser() { window.makeKeyAndOrderFront(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { if !flag { window.makeKeyAndOrderFront(nil) }; return true }
    func applicationWillTerminate(_ notification: Notification) { viewer?.close(); model.persist(); if let keyMonitor { NSEvent.removeMonitor(keyMonitor) } }
    func application(_ application: NSApplication, open urls: [URL]) { if ready { openURLs(urls) } else { pendingURLs.append(contentsOf: urls) } }
    func installMenu() {
        let main = NSMenu()
        func menu(_ title: String) -> NSMenu { let item = NSMenuItem(); let submenu = NSMenu(title: title); item.submenu = submenu; main.addItem(item); return submenu }
        func entry(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "", target: AnyObject? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = target; menu.addItem(item)
        }
        let app = menu("Bild-Atelier")
        entry(app,"Über Bild-Atelier",#selector(NSApplication.orderFrontStandardAboutPanel(_:)),target: NSApp)
        app.addItem(.separator()); entry(app,"Einstellungen …",#selector(settings),",",target:self)
        app.addItem(.separator()); entry(app,"Bild-Atelier ausblenden",#selector(NSApplication.hide(_:)),"h",target:NSApp)
        entry(app,"Bild-Atelier beenden",#selector(NSApplication.terminate(_:)),"q",target:NSApp)
        let file = menu("Ablage"); entry(file,"Ordner hinzufügen …",#selector(addFolder),"o",target:self); entry(file,"Neue Ordnergruppe …",#selector(newGroup),target:self)
        file.addItem(.separator()); entry(file,"Fenster schließen",#selector(NSWindow.performClose(_:)),"w")
        let edit = menu("Bearbeiten")
        entry(edit,"Ausschneiden",#selector(cutSelection),"x",target:self)
        entry(edit,"Kopieren",#selector(copySelection),"c",target:self)
        entry(edit,"Einfügen",#selector(pasteSelection),"v",target:self)
        entry(edit,"Hierher bewegen",#selector(moveSelectionHere),"v",target:self)
        edit.items.last?.keyEquivalentModifierMask = [.command, .option]
        entry(edit,"Alles auswählen",#selector(selectEverything),"a",target:self)
        edit.addItem(.separator())
        entry(edit,"Duplizieren",#selector(duplicateSelection),"d",target:self)
        entry(edit,"Umbenennen …",#selector(renameSelection),target:self)
        entry(edit,"Verschieben nach …",#selector(moveSelectionToFolder),target:self)
        entry(edit,"In den Papierkorb …",#selector(trashSelection),"\u{8}",target:self)
        let view = menu("Ansicht"); entry(view,"Ordner aktualisieren",#selector(refresh),"r",target:self); entry(view,"Ordnerleiste ein-/ausblenden",#selector(toggleSidebar),target:self)
        let win = menu("Fenster"); entry(win,"Browser",#selector(showBrowser),target:self); entry(win,"Minimieren",#selector(NSWindow.performMiniaturize(_:)),"m"); NSApp.windowsMenu = win
        let help = menu("Hilfe"); entry(help,"Bedienung und Tastenkürzel …",#selector(settings),target:self)
        NSApp.mainMenu = main
    }
}

@main enum BildAtelier {
    static func main() {
        if CommandLine.arguments.contains("--performance-test") { PerformanceChecks.run(); return }
        if CommandLine.arguments.contains("--self-test") { SelfTests.run(); return }
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
