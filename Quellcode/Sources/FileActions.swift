import AppKit

struct FileUnit {
    let url: URL
    let sidecar: URL?
    let sharedSidecar: Bool
    let directory: Bool
}

enum FileActions {
    // Resolve companions afresh on the worker, including external Finder paste.
    // One sidecar shared with an unselected RAW is retained at its source.
    static func units(_ urls: [URL]) throws -> [FileUnit] {
        let unique = Array(Set(urls.map { $0.standardizedFileURL })).sorted { $0.path < $1.path }
        let roots = unique.filter { candidate in !unique.contains { $0 != candidate && candidate.path.hasPrefix($0.path + "/") } }
        let selected = Set(roots.map(\.path))
        var scans: [String: [MediaItem]] = [:]
        var result: [FileUnit] = []
        for url in roots {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw failure("Symbolische Verknüpfungen werden nicht verändert: \(url.lastPathComponent)") }
            if values.isDirectory == true {
                result.append(FileUnit(url: url, sidecar: nil, sharedSidecar: false, directory: true)); continue
            }
            let parent = url.deletingLastPathComponent()
            if scans[parent.path] == nil { scans[parent.path] = try DirectoryScan.read(parent, operation: Operation()).items }
            let siblings = scans[parent.path] ?? []
            let sidecar = siblings.first { $0.url == url }?.sidecar?.url
            let shared = sidecar != nil && siblings.contains { $0.sidecar?.url == sidecar && !selected.contains($0.id) }
            result.append(FileUnit(url: url, sidecar: sidecar, sharedSidecar: shared, directory: false))
        }
        return result
    }
    static func failure(_ message: String) -> NSError { NSError(domain: "BildAtelier.Files", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    static func companion(for unit: FileUnit, target: URL) -> URL? {
        guard let sidecar = unit.sidecar else { return nil }
        let sourceKey = sidecar.deletingPathExtension().lastPathComponent
        let originalStem = unit.url.deletingPathExtension().lastPathComponent
        let targetStem = target.deletingPathExtension().lastPathComponent
        let key: String
        if sourceKey == unit.url.lastPathComponent { key = target.lastPathComponent }
        else if sourceKey == originalStem + "_" + unit.url.pathExtension.lowercased() {
            key = targetStem + "_" + target.pathExtension.lowercased()
        } else { key = targetStem }
        return target.deletingLastPathComponent().appendingPathComponent(key + "." + sidecar.pathExtension)
    }
    static func destination(for unit: FileUnit, in folder: URL, name: String? = nil) throws -> URL {
        let fm = FileManager.default
        let targetFolder = folder.resolvingSymlinksInPath().standardizedFileURL
        if unit.directory && (targetFolder == unit.url || targetFolder.path.hasPrefix(unit.url.path + "/")) {
            throw failure("Ein Ordner kann nicht in sich selbst kopiert oder verschoben werden.")
        }
        let requested = targetFolder.appendingPathComponent(name ?? unit.url.lastPathComponent)
        func occupied(_ url: URL) -> Bool {
            fm.fileExists(atPath: url.path) || (companion(for: unit, target: url).map { fm.fileExists(atPath: $0.path) } ?? false)
        }
        if name != nil {
            guard !occupied(requested) else { throw failure("Der Name ist bereits vergeben: \(requested.lastPathComponent)") }
            return requested
        }
        if !occupied(requested) { return requested }
        let ext = unit.directory ? "" : requested.pathExtension
        let stem = ext.isEmpty ? requested.lastPathComponent : requested.deletingPathExtension().lastPathComponent
        var number = 1
        while true {
            let suffix = number == 1 ? " Kopie" : " Kopie \(number)"
            let candidate = targetFolder.appendingPathComponent(stem + suffix + (ext.isEmpty ? "" : "." + ext))
            if !occupied(candidate) { return candidate }; number += 1
        }
    }
    static func transfer(_ unit: FileUnit, to target: URL, move: Bool, moveSidecar: Bool) throws {
        let fm = FileManager.default
        if move { try fm.moveItem(at: unit.url, to: target) }
        else { try fm.copyItem(at: unit.url, to: target) }
        do {
            if let sidecar = unit.sidecar, let companion = companion(for: unit, target: target) {
                // Preserve Nitro's naming convention so Nitro can also find the copy.
                if move && moveSidecar { try fm.moveItem(at: sidecar, to: companion) }
                else { try fm.copyItem(at: sidecar, to: companion) }
            }
        } catch {
            do {
                if move { try fm.moveItem(at: target, to: unit.url) }
                else { try fm.removeItem(at: target) }
            } catch let rollbackError {
                throw failure("XMP konnte nicht übertragen werden. Rücknahme fehlgeschlagen; Datei prüfen unter \(target.path): \(rollbackError.localizedDescription)")
            }
            throw error
        }
    }
}

extension AppModel {
    func copyFiles(cut: Bool = false) {
        guard !fileOperationBusy, !selectedItems.isEmpty else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects(selectedItems.map { $0.url as NSURL })
        cutPaths = cut ? Set(selectedItems.map(\.id)) : []
        cutPasteboardChange = cut ? board.changeCount : -1
    }
    var pasteURLs: [URL] {
        (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    var canPasteFiles: Bool { currentURL != nil && !fileOperationBusy && !pasteURLs.isEmpty }
    func pasteFiles(forceMove: Bool = false) {
        guard let destination = currentURL, canPasteFiles else { return }
        let urls = pasteURLs
        let move = forceMove || (NSPasteboard.general.changeCount == cutPasteboardChange && Set(urls.map(\.path)) == cutPaths)
        performTransfers(urls, destination: destination, move: move)
    }
    func duplicateFiles() {
        guard !selectedItems.isEmpty else { return }
        performTransfers(selectedItems.map(\.url), destination: nil, move: false)
    }
    func moveFilesToFolder() {
        guard !fileOperationBusy, !selectedItems.isEmpty else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.prompt = "Verschieben"; panel.message = "Zielordner für die ausgewählten Dateien"
        if panel.runModal() == .OK, let url = panel.url { performTransfers(selectedItems.map(\.url), destination: url, move: true) }
    }
    private func performTransfers(_ urls: [URL], destination: URL?, move: Bool, rename: String? = nil) {
        guard !fileOperationBusy else { return }; fileOperationBusy = true
        let origin = currentURL
        fileQueue.addOperation { [weak self] in
            var errors: [String] = [], results: [URL] = [], completed: [URL] = []
            do {
                let units = try FileActions.units(urls)
                // Copy shared sidecars for all but the final selected owner. If any
                // transfer fails, keep the original sidecar for the remaining owner.
                var remaining: [String: Int] = [:]
                for unit in units { if let xmp = unit.sidecar { remaining[xmp.path, default: 0] += 1 } }
                for unit in units {
                    do {
                        let folder = destination ?? unit.url.deletingLastPathComponent()
                        if move && rename == nil && folder.resolvingSymlinksInPath() == unit.url.deletingLastPathComponent() { continue }
                        let target = try FileActions.destination(for: unit, in: folder, name: rename)
                        let lastOwner = unit.sidecar.map { remaining[$0.path] == 1 } ?? false
                        try FileActions.transfer(unit, to: target, move: move, moveSidecar: !unit.sharedSidecar && lastOwner)
                        if let xmp = unit.sidecar { remaining[xmp.path, default: 1] -= 1 }
                        results.append(target); completed.append(unit.url)
                    } catch { errors.append("\(unit.url.lastPathComponent): \(error.localizedDescription)") }
                }
            } catch { errors.append(error.localizedDescription) }
            DispatchQueue.main.async {
                guard let self else { return }; self.fileOperationBusy = false
                if move {
                    self.cutPaths.subtract(completed.map(\.path))
                    // Do not leave stale cut URLs that could later move a newly created file.
                    if self.cutPasteboardChange == NSPasteboard.general.changeCount {
                        let remaining = urls.filter { !completed.contains($0) }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.writeObjects(remaining.map { $0 as NSURL })
                        self.cutPasteboardChange = NSPasteboard.general.changeCount
                    }
                }
                if self.currentURL == origin { self.pendingRevealURL = results.first(where: { $0.deletingLastPathComponent() == origin }) }
                self.refreshFileLocations(urls + results); self.refresh()
                self.reportFileErrors(errors)
            }
        }
    }
    func renameFile() {
        guard !fileOperationBusy, selectedItems.count == 1, let item = selectedItems.first else { return }
        let alert = NSAlert(); alert.messageText = "Umbenennen"
        alert.informativeText = "Eine zugehörige XMP-Datei wird ebenfalls zugeordnet."
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24)); input.stringValue = item.url.lastPathComponent
        alert.accessoryView = input; alert.addButton(withTitle: "Umbenennen"); alert.addButton(withTitle: "Abbrechen")
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name != item.url.lastPathComponent else { return }
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":"), !name.contains("\0") else {
            reportFileErrors(["Bitte einen gültigen Dateinamen ohne / oder : eingeben."]); return
        }
        performTransfers([item.url], destination: item.url.deletingLastPathComponent(), move: true, rename: name)
    }
    func trashFiles() {
        guard !fileOperationBusy, !selectedItems.isEmpty else { return }
        let urls = selectedItems.map(\.url)
        let alert = NSAlert(); alert.alertStyle = .warning
        alert.messageText = "\(urls.count) ausgewählte Objekte in den Papierkorb verschieben?"
        alert.informativeText = "Ordner werden mit ihrem Inhalt verschoben. Zugehörige XMP-Dateien werden mitgenommen, sofern sie nicht auch zu nicht ausgewählten Bildern gehören. Wiederherstellen ist im Finder über den Papierkorb möglich."
        alert.addButton(withTitle: "In den Papierkorb"); alert.addButton(withTitle: "Abbrechen")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        fileOperationBusy = true
        fileQueue.addOperation { [weak self] in
            var errors: [String] = []
            do {
                let units = try FileActions.units(urls)
                var remaining: [String: Int] = [:]
                for unit in units { if let xmp = unit.sidecar { remaining[xmp.path, default: 0] += 1 } }
                for unit in units {
                    do {
                        try FileManager.default.trashItem(at: unit.url, resultingItemURL: nil)
                        if let xmp = unit.sidecar {
                            remaining[xmp.path, default: 1] -= 1
                            if !unit.sharedSidecar && remaining[xmp.path] == 0 {
                                try FileManager.default.trashItem(at: xmp, resultingItemURL: nil)
                            }
                        }
                    } catch { errors.append("\(unit.url.lastPathComponent): \(error.localizedDescription)") }
                }
            } catch { errors.append(error.localizedDescription) }
            DispatchQueue.main.async {
                guard let self else { return }; self.fileOperationBusy = false; self.refreshFileLocations(urls); self.refresh(); self.reportFileErrors(errors)
            }
        }
    }
    func reportFileErrors(_ errors: [String]) {
        guard !errors.isEmpty else { return }
        let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = "Nicht alle Dateiaktionen konnten ausgeführt werden"
        alert.informativeText = errors.prefix(12).joined(separator: "\n") + (errors.count > 12 ? "\n… und \(errors.count - 12) weitere Fehler." : "")
        alert.runModal()
    }
}

// Retained by its menu, unlike ephemeral target/action bridge objects.
final class FileMenuItem: NSMenuItem {
    let handler: () -> Void
    init(_ title: String, enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self; isEnabled = enabled
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { handler() }
}

extension AppModel {
    func fileContextMenu(for item: MediaItem) -> NSMenu {
        prepareContext(item)
        let menu = NSMenu(); menu.autoenablesItems = false
        menu.addItem(FileMenuItem(item.isDirectory ? "Ordner öffnen" : "Im Vollbild anzeigen") { self.selectedID = item.id; self.activate(item) })
        menu.addItem(FileMenuItem("Zum Ordner wechseln") { self.revealContainingFolder(item) })
        menu.addItem(FileMenuItem("Im Finder anzeigen") { NSWorkspace.shared.activateFileViewerSelecting(self.selectedItems.map(\.url)) })
        menu.addItem(.separator())
        let ready = !fileOperationBusy
        menu.addItem(FileMenuItem("Kopieren", enabled: ready) { self.copyFiles() })
        menu.addItem(FileMenuItem("Ausschneiden", enabled: ready) { self.copyFiles(cut: true) })
        menu.addItem(FileMenuItem("Hier einfügen", enabled: canPasteFiles) { self.pasteFiles() })
        menu.addItem(FileMenuItem("Duplizieren", enabled: ready) { self.duplicateFiles() })
        menu.addItem(FileMenuItem("Verschieben nach …", enabled: ready) { self.moveFilesToFolder() })
        menu.addItem(FileMenuItem("Umbenennen …", enabled: ready && selectedItems.count == 1) { self.renameFile() })
        menu.addItem(.separator())
        menu.addItem(FileMenuItem("In den Papierkorb …", enabled: ready) { self.trashFiles() })
        return menu
    }
}
