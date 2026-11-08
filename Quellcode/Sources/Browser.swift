import AppKit
import SwiftUI

struct BrowserView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    var body: some View {
        HSplitView {
            if model.sidebarVisible { FolderSidebar(model: model).frame(minWidth: 270, idealWidth: 320, maxWidth: 420) }
            VStack(spacing: 0) {
                toolbar
                Divider()
                FacetBar(model: model)
                Divider()
                ZStack {
                    Color(nsColor: .controlBackgroundColor)
                    if model.busy && model.displayItems.isEmpty { ProgressView("Ordner wird gelesen …") }
                    else if let error = model.error { emptyState("folder.badge.questionmark", "Ordner nicht verfügbar", error) }
                    else if model.folder == nil { emptyState("photo.on.rectangle.angled", "Raum für deine Bilder", "Füge über + in der Seitenleiste einen Ordner hinzu.\nDeine Bilder und Videos bleiben an ihrem Speicherort.") }
                    else if model.displayItems.isEmpty && (model.searchActive || !model.facetSelections.isEmpty) { emptyState("line.3.horizontal.decrease.circle", "Keine passenden Dateien", "Ändere den Suchtext oder die Filter.") }
                    else if model.displayItems.isEmpty { emptyState("photo", "Dieser Ordner ist leer", "Hier werden Unterordner, Bilder und Videos angezeigt.") }
                    else if preferences.listMode { MediaTable(model: model, preferences: preferences, updates: model.metadataUpdates) }
                    else { MediaGrid(model: model, preferences: preferences) }
                }
                Divider()
                HStack(spacing: 10) {
                    if model.busy || model.sorting || model.fileOperationBusy { ProgressView().controlSize(.mini) }
                    if model.fileOperationBusy { Text("Dateien werden bearbeitet …") }
                    else if model.searchActive {
                        Text("\(model.displayItems.count) Treffer · \(model.searchScanned) Dateien geprüft")
                        if model.searchFromMemory { Text("RAM-Cache").foregroundStyle(.secondary) }
                        if model.searchSkipped > 0 { Text("\(model.searchSkipped) Ordner nicht lesbar").foregroundStyle(.orange) }
                    } else { Text("\(model.directoryCount) Ordner · \(model.mediaItems.count - model.videoCount) Bilder · \(model.videoCount) Videos") }
                    if model.selectedIDs.count > 1 { Text("\(model.selectedIDs.count) ausgewählt") }
                    Spacer()
                    if let selected = model.selected { Text(selected.url.lastPathComponent).lineLimit(1); Text(selected.value(.size)).foregroundStyle(.tertiary) }
                }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 30)
            }.frame(minWidth: 760, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in if let url { DispatchQueue.main.async { model.add([url]) } } }
            }; return !providers.isEmpty
        }
    }
    private var toolbar: some View {
        HStack(spacing: 10) {
            if !model.sidebarVisible { icon("sidebar.left", "Ordnerleiste anzeigen") { model.sidebarVisible = true } }
            icon("chevron.left", "Zurück") { model.goBack() }.disabled(model.history.isEmpty)
            icon("arrow.up", "Übergeordneter Ordner") { model.goUp() }.disabled(!model.canGoUp)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.folder?.name ?? "Bild-Atelier").font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Text(model.folder?.path ?? "Deine Bilder. Dein Blick.").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }.frame(minWidth: 60, maxWidth: .infinity, alignment: .leading)
            Picker("Ansicht", selection: $preferences.listMode) {
                Image(systemName: "square.grid.2x2").tag(false)
                Image(systemName: "list.bullet").tag(true)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 76).help("Thumbnails oder detaillierte Liste")
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Dateien und Metadaten", text: $model.searchQuery)
                    .textFieldStyle(.plain).accessibilityLabel("Dateien und Metadaten durchsuchen")
                if !model.searchQuery.isEmpty {
                    Button { model.searchQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).help("Suche löschen")
                }
            }.padding(6).background(Color(nsColor: .textBackgroundColor)).cornerRadius(6)
                .frame(width: 185).help("Sucht im aktuellen Ordner und allen Unterordnern nach Dateinamen, EXIF, IPTC und XMP. Mehrere Wörter müssen alle vorkommen.")
                .disabled(model.currentURL == nil)
            if !preferences.listMode {
                Image(systemName: "photo").font(.system(size: 11)).foregroundStyle(.secondary)
                Slider(value: $preferences.thumbnailSize, in: 120...420).frame(width: 90).help("Thumbnailgröße")
                icon(preferences.showText ? "text.below.photo.fill" : "text.below.photo", preferences.showText ? "Textzeilen ausblenden" : "Textzeilen anzeigen") { preferences.showText.toggle() }
            }
            Menu {
                ForEach(MetaField.allCases.filter { [.name, .size, .modified, .taken, .kind].contains($0) }) { field in
                    Button { model.setSort(field, ascending: model.ascending) } label: { if model.sortField == field { Label(field.label, systemImage: "checkmark") } else { Text(field.label) } }
                }
                Divider(); Button(model.ascending ? "Absteigend sortieren" : "Aufsteigend sortieren") { model.setSort(model.sortField, ascending: !model.ascending) }
            } label: { Image(systemName: "arrow.up.arrow.down") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22).help("Sortierung")
            icon("arrow.clockwise", "Ordner aktualisieren · ⌘R") { model.refresh() }
            icon("gearshape", "Einstellungen · ⌘,") { model.showSettings?() }
        }.padding(.horizontal, 18).frame(height: 65)
    }
    private func emptyState(_ symbol: String, _ title: String, _ detail: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 44, weight: .ultraLight)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 23, weight: .medium))
            Text(detail).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

func icon(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: symbol).font(.system(size: 15)).frame(width: 25, height: 26) }
        .buttonStyle(.plain).foregroundStyle(.secondary).help(help).accessibilityLabel(help)
}

struct SidebarEntry: Identifiable {
    var id: String
    var title: String
    var root: FolderRecord?
    var url: URL?
    var depth: Int = 0
    var section: String? = nil
}

struct FolderSidebar: View {
    @ObservedObject var model: AppModel
    @StateObject private var search = PinnedSearch()
    @FocusState private var searchFocused: Bool
    @AtelierState(wrappedValue: true) private var pinnedExpanded: Bool
    @AtelierState(wrappedValue: true) private var recentExpanded: Bool
    @AtelierState(wrappedValue: []) private var collapsedGroups: Set<String>
    private var entries: [SidebarEntry] {
        var rows: [SidebarEntry] = []
        func append(_ root: FolderRecord) {
            rows.append(SidebarEntry(id: root.id, title: root.name, root: root, url: root.url))
            // Children are cached in ascending natural order. The stack pops its last
            // element first, so pinned trees use that order directly to display Z–A.
            func stackedChildren(_ path: String, depth: Int) -> [(URL, Int)] {
                let children = model.childFolders[path] ?? []
                return (root.pinned ? children : Array(children.reversed())).map { ($0, depth) }
            }
            var stack: [(URL, Int)] = []
            if model.expandedPaths.contains(root.path) { stack = stackedChildren(root.path, depth: 1) }
            while let (url, depth) = stack.popLast() {
                rows.append(SidebarEntry(id: root.id + ":" + url.path, title: url.lastPathComponent, root: root, url: url, depth: depth))
                if model.expandedPaths.contains(url.path) { stack.append(contentsOf: stackedChildren(url.path, depth: depth + 1)) }
            }
        }
        rows.append(SidebarEntry(id: "pinned", title: "Angepinnt", section: "pinned"))
        if search.active {
            for hit in search.hits { rows.append(SidebarEntry(id: "search:" + hit.id, title: hit.url.lastPathComponent, root: hit.root, url: hit.url, depth: hit.url == hit.root.url ? 0 : 1)) }
        } else if pinnedExpanded {
            model.folders.filter { $0.pinned && $0.group == nil }.forEach(append)
            for group in model.groups {
                rows.append(SidebarEntry(id: "group:" + group, title: group, section: "group"))
                if !collapsedGroups.contains(group) { model.folders.filter { $0.pinned && $0.group == group }.forEach(append) }
            }
        }
        rows.append(SidebarEntry(id: "recent", title: "Zuletzt geöffnet", section: "recent"))
        if recentExpanded { model.recent.forEach(append) }
        return rows
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ordner").font(.system(size: 15, weight: .semibold)); Spacer()
                icon("plus", "Ordner hinzufügen") { model.addFolders() }
                icon("sidebar.left", "Ordnerleiste ausblenden") { model.sidebarVisible = false }
            }.padding(.horizontal, 16).frame(height: 65)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(entries) { entry in
                        if let section = entry.section {
                            HStack(spacing: 6) {
                            Button {
                                if section == "pinned" { pinnedExpanded.toggle() }
                                else if section == "recent" { recentExpanded.toggle() }
                                else if collapsedGroups.contains(entry.title) { collapsedGroups.remove(entry.title) } else { collapsedGroups.insert(entry.title) }
                            } label: {
                                HStack {
                                    if section == "group" { Image(systemName: collapsedGroups.contains(entry.title) ? "chevron.right" : "chevron.down").font(.system(size: 9)) }
                                    Text(entry.title).font(.system(size: 13)); if section != "pinned" { Spacer() }
                                }.foregroundStyle(section == "group" ? Color.secondary : Color.accentColor).padding(.vertical, 8)
                            }.buttonStyle(.plain).contextMenu {
                                Button("Neue Gruppe …") { model.createGroup() }
                                if section == "group" { Button("Gruppe entfernen (Ordner behalten)") {
                                    model.groups.removeAll { $0 == entry.title }
                                    for i in model.folders.indices where model.folders[i].group == entry.title { model.folders[i].group = nil }; model.persist()
                                } }
                            }
                            if section == "pinned" {
                                Spacer(minLength: 24)
                                TextField("Suchen …", text: $search.query).textFieldStyle(.roundedBorder)
                                    .focused($searchFocused)
                                    .frame(width: searchFocused || !search.query.isEmpty ? 140 : 75).help("Angepinnte Ordner inklusive Unterordner durchsuchen")
                                Menu {
                                    Toggle("Im gesamten Pfad suchen", isOn: $search.searchPath)
                                    Picker("Gruppe", selection: $search.group) {
                                        Text("Alle Gruppen").tag("")
                                        ForEach(model.groups, id: \.self) { Text($0).tag($0) }
                                    }
                                    Button("Suche zurücksetzen") { search.query = ""; search.group = "" }
                                } label: { Image(systemName: "line.3.horizontal.decrease.circle") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
                            }
                            }
                            if section == "pinned" && search.active {
                                if search.busy { ProgressView("Unterordner durchsuchen …").controlSize(.small) }
                                else { Text("\(search.hits.count) Ordner gefunden").font(.caption).foregroundStyle(.secondary) }
                                if search.inaccessible { Text("Einige Ordner konnten nicht gelesen werden.").font(.caption).foregroundStyle(.secondary) }
                            }
                        } else if let root = entry.root, let url = entry.url {
                            HStack(spacing: 0) {
                                if model.childFolders[url.path]?.isEmpty == false {
                                    icon(model.expandedPaths.contains(url.path) ? "chevron.down" : "chevron.right", "Unterordner ein- oder ausklappen") { model.toggleExpanded(url) }
                                } else {
                                    Color.clear.frame(width: 25, height: 26).accessibilityHidden(true)
                                }
                                Button {
                                    if model.currentURL?.standardizedFileURL == url.standardizedFileURL { model.toggleExpanded(url) }
                                    else if entry.depth == 0 { model.selectFolder(root.id) }
                                    else { if model.activeFolder != root.id { model.selectFolder(root.id) }; model.navigate(to: url) }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "folder").foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.title).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                                            if entry.id.hasPrefix("search:") { Text(url.path).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                                        }; Spacer(minLength: 0)
                                        if entry.depth == 0 && root.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.tertiary) }
                                    }.padding(.horizontal, 6).padding(.vertical, 8)
                                        .background(model.currentURL?.path == url.path ? Color.accentColor.opacity(0.13) : .clear).cornerRadius(7)
                                }.buttonStyle(.plain).help(url.path).contextMenu {
                                    Text(url.path)
                                    if entry.depth == 0 {
                                        Button(root.pinned ? "Loslösen" : "Anpinnen") { model.pin(root) }
                                        if !model.groups.isEmpty { Menu("In Gruppe anpinnen") { ForEach(model.groups, id: \.self) { group in Button(group) { model.pin(root, group: group) } } } }
                                        Button("Neue Gruppe …") { model.createGroup() }
                                        Button("Aus der Leiste entfernen") { model.remove(root) }
                                    }
                                    Button("Im Finder anzeigen") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                }
                            }.padding(.leading, CGFloat(entry.depth) * 16)
                                .onAppear { model.loadChildren(url) }
                        }
                    }
                    if model.folders.isEmpty { Text("Mit + einen Ordner hinzufügen\noder einen Ordner hierher ziehen.").font(.system(size: 11)).foregroundStyle(.tertiary).lineSpacing(5) }
                }.padding(.horizontal, 14).padding(.bottom, 20)
            }
            HStack { Text("BILD-ATELIER").font(.system(size: 9, weight: .medium)).tracking(1.7).foregroundStyle(.tertiary); Spacer() }.padding(18)
        }.background(.regularMaterial)
        .onChange(of: search.query) { _ in search.search(model.folders) }
        .onChange(of: search.group) { _ in search.search(model.folders) }
        .onChange(of: search.searchPath) { _ in search.search(model.folders) }
        .onChange(of: model.folders.map { $0.id + $0.path + String($0.pinned) + ($0.group ?? "") }) { _ in search.search(model.folders) }
    }
}

struct ThumbnailView: View {
    @ObservedObject var item: MediaItem
    @AtelierState(wrappedValue: nil) private var image: NSImage?
    @AtelierState(wrappedValue: false) private var loaded: Bool
    var maxPixel: Int = 256
    @AtelierState(wrappedValue: nil) private var operation: ThumbnailRequest?
    var body: some View {
        ZStack {
            Color.black.opacity(0.035)
            if item.isDirectory { Image(systemName: "folder.fill").font(.system(size: 64, weight: .light)).foregroundStyle(Color.accentColor) }
            else if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit) }
            else { Image(systemName: loaded ? "exclamationmark.triangle" : (item.video ? "film" : "photo")).font(.system(size: 26, weight: .ultraLight)).foregroundStyle(.secondary) }
            if item.sidecar != nil {
                VStack { HStack { Spacer(); Text("XMP").font(.system(size: 9, weight: .semibold)).padding(4).background(.black.opacity(0.6)).foregroundStyle(.white).cornerRadius(3) }; Spacer() }.padding(6).help(item.renderWarning ?? item.value(.xmpStatus))
            }
            if item.video {
                VStack { Spacer(); HStack { Image(systemName: "play.fill"); Spacer(); Text(item.value(.duration) == "—" ? "Video" : item.value(.duration)) } }.font(.system(size: 10, weight: .medium)).foregroundStyle(.white).padding(8).background(alignment: .bottom) { LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom) }
            }
        }.clipped().onAppear { load() }
            .onChange(of: item.cacheKey + "-" + String(maxPixel)) { _ in load() }
            .onDisappear { operation?.cancel(); operation = nil; image = nil; loaded = false }
    }
    private func load() {
        operation?.cancel(); guard !item.isDirectory else { return }
        operation = ThumbnailStore.shared.load(item, maxPixel: maxPixel) { image in self.image = image; loaded = true }
    }
}

struct MediaGrid: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: preferences.thumbnailSize), spacing: 18)], alignment: .leading, spacing: 22) {
                    ForEach(model.displayItems) { item in
                        ThumbnailCard(item: item, preferences: preferences, selected: model.selectedIDs.contains(item.id))
                            .id(item.id).contentShape(Rectangle())
                            .onAppear { DispatchQueue.main.async { if model.displayIndex[item.id] != nil { model.requestMetadata(item) } } }
                            .onTapGesture(count: 2) { focusBrowser(); model.selectedID = item.id; model.activate(item) }
                            .onTapGesture { let flags = NSApp.currentEvent?.modifierFlags ?? []; focusBrowser(); model.select(item, modifiers: flags) }
                            .contextMenu { MediaContextActions(model: model, item: item) }
                    }
                }.padding(22)
            }.onChange(of: model.selectedID) { id in if let id { proxy.scrollTo(id) } }
                .onAppear { if let id = model.selectedID { DispatchQueue.main.async { proxy.scrollTo(id) } } }
        }
    }
}

struct ThumbnailCard: View {
    @ObservedObject var item: MediaItem
    @ObservedObject var preferences: Preferences
    var selected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ThumbnailView(item: item, maxPixel: Int(preferences.thumbnailSize * 2)).frame(height: preferences.thumbnailSize * 0.73).clipShape(RoundedRectangle(cornerRadius: 5))
                .padding(4).background(selected ? Color.accentColor.opacity(0.10) : .clear)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1))
            if item.isDirectory { Text(item.url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(2).padding(.horizontal, 5) }
            else if preferences.showText {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(preferences.lines.prefix(4).enumerated()), id: \.offset) { _, key in
                        if let field = MetaField(rawValue: key) {
                            Text(item.value(field)).font(.system(size: 11, weight: field == .name ? .medium : .regular)).foregroundStyle(field == .name ? Color.primary : Color.secondary).lineLimit(1).truncationMode(.middle).help("\(field.label): \(item.value(field))")
                        }
                    }
                }.padding(.horizontal, 5)
            }
        }.help(item.url.lastPathComponent).accessibilityLabel(item.url.lastPathComponent)
    }
}

struct MediaTable: NSViewRepresentable {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    @ObservedObject var updates: MetadataUpdates
    func makeCoordinator() -> Coordinator { Coordinator(model: model, preferences: preferences) }
    func makeNSView(context: Context) -> NSScrollView {
        let table = FileTableView(); table.contextProvider = { [weak model] row in
            guard let model, row >= 0, row < model.displayItems.count else { return nil }
            return model.fileContextMenu(for: model.displayItems[row])
        }; table.headerView = NSTableHeaderView(); table.rowHeight = 30
        table.usesAlternatingRowBackgroundColors = true; table.style = .fullWidth
        table.allowsMultipleSelection = true; table.allowsColumnReordering = true
        table.columnAutoresizingStyle = .noColumnAutoresizing; table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.target = context.coordinator; table.doubleAction = #selector(Coordinator.openItem)
        let menu = NSMenu(); menu.delegate = context.coordinator; table.headerView?.menu = menu
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        context.coordinator.table = table; context.coordinator.sync(); return scroll
    }
    func updateNSView(_ nsView: NSScrollView, context: Context) { context.coordinator.sync() }
    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
        let model: AppModel; let preferences: Preferences
        weak var table: NSTableView?
        var syncing = false
        var lastSelection: String?
        var lastItemsRevision = -1
        var lastMetadataRevision = -1
        init(model: AppModel, preferences: Preferences) { self.model = model; self.preferences = preferences }
        func sync() {
            guard let table else { return }; syncing = true; defer { syncing = false }
            let columnsChanged = table.tableColumns.map({ $0.identifier.rawValue }) != preferences.columns.map(\.rawValue)
            if columnsChanged {
                table.tableColumns.forEach(table.removeTableColumn)
                let widths = Preferences.defaults.dictionary(forKey: "columnWidths") as? [String: Double] ?? [:]
                for field in preferences.columns {
                    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(field.rawValue)); column.title = field.label
                    column.minWidth = 70; column.width = widths[field.rawValue] ?? (field == .name ? 260 : 160)
                    column.sortDescriptorPrototype = NSSortDescriptor(key: field.rawValue, ascending: true)
                    table.addTableColumn(column)
                }
            }
            if table.sortDescriptors.first?.key != model.sortField.rawValue || table.sortDescriptors.first?.ascending != model.ascending {
                table.sortDescriptors = [NSSortDescriptor(key: model.sortField.rawValue, ascending: model.ascending)]
            }
            if columnsChanged || lastItemsRevision != model.displayRevision {
                table.reloadData(); lastItemsRevision = model.displayRevision
            } else if lastMetadataRevision != model.metadataUpdates.revision {
                let visible = table.rows(in: table.visibleRect)
                if visible.location != NSNotFound && visible.length > 0 { table.reloadData(forRowIndexes: IndexSet(integersIn: visible.location..<min(model.displayItems.count, NSMaxRange(visible))), columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns)) }
            }
            lastMetadataRevision = model.metadataUpdates.revision
            let rows = IndexSet(model.selectedIDs.compactMap { model.displayIndex[$0] })
            if table.selectedRowIndexes != rows { table.selectRowIndexes(rows, byExtendingSelection: false) }
            if lastSelection != model.selectedID, let id = model.selectedID, let row = model.displayIndex[id] { table.scrollRowToVisible(row) }
            lastSelection = model.selectedID
        }
        func numberOfRows(in tableView: NSTableView) -> Int { model.displayItems.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < model.displayItems.count, let column = tableColumn, let field = MetaField(rawValue: column.identifier.rawValue) else { return nil }
            let item = model.displayItems[row]
            if !item.metadataLoaded && preferences.columns.contains(where: \.needsMetadata) { DispatchQueue.main.async { [weak model] in if model?.itemIndex[item.id] != nil { model?.requestMetadata(item) } } }
            let view = tableView.makeView(withIdentifier: column.identifier, owner: nil) as? NSTableCellView ?? NSTableCellView()
            if view.textField == nil {
                let text = NSTextField(labelWithString: ""); text.font = .systemFont(ofSize: 12); text.lineBreakMode = .byTruncatingMiddle
                view.addSubview(text); view.textField = text; text.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([text.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),text.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),text.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
            }
            view.identifier = column.identifier; view.textField?.stringValue = (model.displayItems[row].isDirectory && field == .name ? "📁  " : "") + model.displayItems[row].value(field); view.toolTip = model.displayItems[row].value(field); return view
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !syncing, let table else { return }
            let ids = Set(table.selectedRowIndexes.filter { $0 < model.displayItems.count }.map { model.displayItems[$0].id })
            let primary = table.selectedRow >= 0 && table.selectedRow < model.displayItems.count ? model.displayItems[table.selectedRow].id : nil
            model.setSelection(ids, primary: primary)
        }
        @objc func openItem() { guard let table, table.clickedRow >= 0, table.clickedRow < model.displayItems.count else { return }; let item = model.displayItems[table.clickedRow]; model.selectedID = item.id; model.activate(item) }
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !syncing, let sort = tableView.sortDescriptors.first, let key = sort.key, let field = MetaField(rawValue: key) else { return }; model.setSort(field, ascending: sort.ascending)
        }
        func tableViewColumnDidMove(_ notification: Notification) {
            guard !syncing, let table else { return }
            let columns = table.tableColumns.compactMap { MetaField(rawValue: $0.identifier.rawValue) }
            if !columns.isEmpty && columns != preferences.columns { preferences.columns = columns }
        }
        func tableViewColumnDidResize(_ notification: Notification) { guard !syncing, let table else { return }; Preferences.defaults.set(Dictionary(uniqueKeysWithValues: table.tableColumns.map { ($0.identifier.rawValue, Double($0.width)) }), forKey: "columnWidths") }
        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            for group in ["Datei", "EXIF", "IPTC", "XMP"] {
                if !menu.items.isEmpty { menu.addItem(.separator()) }
                let title = NSMenuItem(title: group, action: nil, keyEquivalent: ""); title.isEnabled = false; menu.addItem(title)
                for field in MetaField.allCases where field.group == group {
                    let entry = NSMenuItem(title: field.label, action: #selector(toggleColumn(_:)), keyEquivalent: "")
                    entry.target = self; entry.representedObject = field.rawValue; entry.state = preferences.columns.contains(field) ? .on : .off
                    if preferences.columns.count == 1 && preferences.columns.contains(field) { entry.isEnabled = false }
                    menu.addItem(entry)
                }
            }
        }
        @objc func toggleColumn(_ sender: NSMenuItem) { if let key = sender.representedObject as? String, let field = MetaField(rawValue: key) { preferences.toggle(field) } }
    }
}

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    var body: some View {
        TabView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Text unter den Thumbnails").font(.title2.weight(.semibold))
                Text("Bis zu vier Zeilen. Leere Metadaten erscheinen als Gedankenstrich.\nDas Textsymbol in der Symbolleiste blendet alle Zeilen ein oder aus.").font(.callout).foregroundStyle(.secondary)
                ForEach(0..<4, id: \.self) { index in
                    Picker("Zeile \(index + 1)", selection: Binding(get: { preferences.lines[index] }, set: { preferences.lines[index] = $0 })) {
                        Text("Nicht anzeigen").tag("")
                        ForEach(MetaField.allCases) { field in Text("\(field.group) · \(field.label)").tag(field.rawValue) }
                    }
                }
                Toggle("Textzeilen anzeigen", isOn: $preferences.showText)
                Spacer()
            }.padding(28).tabItem { Label("Thumbnails", systemImage: "photo.on.rectangle") }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Spalten in der Detailansicht").font(.title2.weight(.semibold))
                    Text("Auch per Rechtsklick auf die Tabellenüberschriften auswählbar.\nSpalten lassen sich ziehen und in der Breite verändern.").font(.callout).foregroundStyle(.secondary)
                    ForEach(["Datei", "EXIF", "IPTC", "XMP"], id: \.self) { group in
                        Text(group).font(.headline).padding(.top, 8)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                            ForEach(MetaField.allCases.filter { $0.group == group }) { field in
                                Toggle(field.label, isOn: Binding(get: { preferences.columns.contains(field) }, set: { _ in preferences.toggle(field) })).disabled(preferences.columns.count == 1 && preferences.columns.contains(field)).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }.padding(28)
            }.tabItem { Label("Tabellenspalten", systemImage: "tablecells") }
            VStack(alignment: .leading, spacing: 16) {
                Text("Ganz im Bild").font(.title2.weight(.semibold))
                Text("Doppelklick öffnet ein Bild oder Video im Vollbild.").foregroundStyle(.secondary)
                ForEach([("← / →", "Vorherige / nächste Datei"), ("↑", "Vorschauleiste öffnen und fokussieren"), ("← / → in der Leiste", "Vorschau auswählen, ohne das Vollbild zu wechseln"), ("↓ oder Enter", "Auswahl übernehmen und Leiste schließen"), ("i", "EXIF-/IPTC-Overlay ein- oder ausblenden"), ("o", "Original / XMP-Vorschau umschalten"), ("+ / − · Pinch", "Bild vergrößern / verkleinern"), ("0 / 1", "Einpassen / Originalgröße (100 %)"), ("Rechtsziehen · zwei Finger", "Vergrößertes Bild verschieben"), ("Leertaste", "Video abspielen / pausieren"), ("Esc", "Zurück zum Browser")], id: \.0) { key, action in
                    HStack { Text(key).font(.system(size: 12, weight: .medium, design: .monospaced)).frame(width: 185, alignment: .leading); Text(action).font(.system(size: 12)); Spacer() }
                }; Spacer()
            }.padding(28).tabItem { Label("Bedienung", systemImage: "keyboard") }
        }.frame(width: 630, height: 490)
    }
}

private func focusBrowser() {
    if let window = NSApp.keyWindow { window.makeFirstResponder(window.contentView) }
}

final class FileTableView: NSTableView {
    var contextProvider: ((Int) -> NSMenu?)?
    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        return contextProvider?(row)
    }
}

struct MediaContextActions: View {
    @ObservedObject var model: AppModel
    let item: MediaItem
    private var count: Int { model.selectedIDs.contains(item.id) ? model.selectedIDs.count : 1 }
    private func perform(_ action: () -> Void) { focusBrowser(); model.prepareContext(item); action() }
    var body: some View {
        Button(item.isDirectory ? "Ordner öffnen" : "Im Vollbild anzeigen") { perform { model.selectedID = item.id; model.activate(item) } }
        Button("Zum Ordner wechseln") { perform { model.revealContainingFolder(item) } }
        Button("Im Finder anzeigen") { perform { NSWorkspace.shared.activateFileViewerSelecting(model.selectedItems.map(\.url)) } }
        Divider()
        Button("Kopieren") { perform { model.copyFiles() } }.disabled(model.fileOperationBusy)
        Button("Ausschneiden") { perform { model.copyFiles(cut: true) } }.disabled(model.fileOperationBusy)
        Button("Hier einfügen") { perform { model.pasteFiles() } }.disabled(!model.canPasteFiles)
        Button("Duplizieren") { perform { model.duplicateFiles() } }.disabled(model.fileOperationBusy)
        Button("Verschieben nach …") { perform { model.moveFilesToFolder() } }.disabled(model.fileOperationBusy)
        Button("Umbenennen …") { perform { model.renameFile() } }.disabled(model.fileOperationBusy || count != 1)
        Divider()
        Button("In den Papierkorb …") { perform { model.trashFiles() } }.disabled(model.fileOperationBusy)
    }
}
