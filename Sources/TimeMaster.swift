import SwiftUI
import AppKit

struct Event: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var start: Date
    var end: Date
    var style: DisplayStyle = .dots
    var color = 0
    var visible = true
    var x: Double? = nil
    var y: Double? = nil
    var cardWidth: Double? = nil
    var cardHeight: Double? = nil
    var remaining: Int { max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: end)).day ?? 0) }
    var ratio: Double { guard end > start else { return 0 }; return min(1, max(0, end.timeIntervalSinceNow / end.timeIntervalSince(start))) }
    var totalDays: Int { max(1, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: start), to: Calendar.current.startOfDay(for: end)).day ?? 1) }
    var tint: Color { [Color.indigo, .teal, .pink, .orange, .gray][min(4, max(0, color))] }
    var status: String { Date() < start ? "尚未开始" : (end <= Date() ? "已到期" : (remaining == 0 ? "今天到期" : "天后")) }
}
enum DisplayStyle: String, Codable, CaseIterable { case dots = "点阵", ring = "圆环", timeline = "刻度" }

// Pure geometry, shared by native drag handling and regression tests.
struct CardSnap {
    static let margin: CGFloat = 14
    static func snapped(_ window: CGRect, screens: [CGRect], neighbors: [CGRect], threshold: CGFloat = 16, gap: CGFloat = 12) -> CGRect {
        var card = window.insetBy(dx: margin, dy: margin)
        let original = card
        var xs: [CGFloat] = [], ys: [CGFloat] = []
        if let screen = screens.max(by: { area($0.intersection(card)) < area($1.intersection(card)) }), screen.intersects(card) {
            xs += [screen.minX + gap, screen.maxX - gap - card.width]
            ys += [screen.minY + gap, screen.maxY - gap - card.height]
        }
        for otherWindow in neighbors {
            let other = otherWindow.insetBy(dx: margin, dy: margin)
            let nearY = card.maxY >= other.minY-gap-threshold && card.minY <= other.maxY+gap+threshold
            let nearX = card.maxX >= other.minX-gap-threshold && card.minX <= other.maxX+gap+threshold
            if nearY { xs += [other.minX-gap-card.width, other.maxX+gap] }
            if nearX { ys += [other.minY-gap-card.height, other.maxY+gap] }
            if abs(card.maxY-other.minY) <= gap+threshold || abs(card.minY-other.maxY) <= gap+threshold {
                xs += [other.minX, other.maxX-card.width]
            }
            if abs(card.maxX-other.minX) <= gap+threshold || abs(card.minX-other.maxX) <= gap+threshold {
                ys += [other.minY, other.maxY-card.height]
            }
        }
        if let x = xs.filter({ abs($0-original.minX) <= threshold }).min(by: { abs($0-original.minX) < abs($1-original.minX) }) { card.origin.x = x }
        if let y = ys.filter({ abs($0-original.minY) <= threshold }).min(by: { abs($0-original.minY) < abs($1-original.minY) }) { card.origin.y = y }
        return card.insetBy(dx: -margin, dy: -margin)
    }
    private static func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width*rect.height }
}

@MainActor final class Store: ObservableObject {
    static let shared = Store()
    @Published var events: [Event] = []
    @Published var showCards = true
    @Published var error: String?
    let url: URL
    init() {
        url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TimeMaster/events.json")
        if FileManager.default.fileExists(atPath: url.path) {
            do { events = try JSONDecoder().decode([Event].self, from: Data(contentsOf: url)) }
            catch { self.error = "无法读取本地事件，原文件已保留：\(error.localizedDescription)" }
        } else if CommandLine.arguments.contains("--demo") {
            let now = Date()
            events = [Event(title: "英语六级", start: Calendar.current.date(byAdding: .day, value: -23, to: now)!, end: Calendar.current.date(byAdding: .day, value: 19, to: now)!), Event(title: "数据库期末", start: now, end: Calendar.current.date(byAdding: .day, value: 37, to: now)!, style: .ring, color: 1)]
            save()
        }
    }
    func save() {
        guard error == nil else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(events).write(to: url, options: .atomic)
        } catch { self.error = "保存失败：\(error.localizedDescription)" }
    }
    func upsert(_ e: Event) {
        if let i = events.firstIndex(where: { $0.id == e.id }) { events[i] = e } else { events.append(e) }
        save(); Windows.shared.refresh(); Windows.shared.applySize(e)
    }
    func remove(_ id: UUID) { events.removeAll { $0.id == id }; save(); GroupStore.shared.prune(id); Windows.shared.refresh() }
    func toggle(_ e: Event) { var e = e; e.visible.toggle(); upsert(e) }
    func setStyle(_ style: DisplayStyle, for e: Event) { var e = e; e.style = style; upsert(e) }
    func commitGeometry(_ id: UUID, frame: CGRect) {
        guard let i = events.firstIndex(where: { $0.id == id }) else { return }
        events[i].x = frame.minX; events[i].y = frame.minY
        let size = CardGeometry.clamp(CGSize(width: frame.width-28,height:frame.height-28))
        events[i].cardWidth = size.width; events[i].cardHeight = size.height
        save()
    }
    func position(_ id: UUID, _ point: NSPoint) {
        guard let i = events.firstIndex(where: { $0.id == id }) else { return }
        events[i].x = point.x; events[i].y = point.y; save()
    }
}

struct PanelMenu: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var preferences = Preferences.shared
    @ObservedObject var groups=GroupStore.shared
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Time Master").font(.headline)
                Spacer()
                Menu {
                    Button("设置…") { Windows.shared.settings() }
                    Menu("桌面图层") {
                        ForEach(CardLayer.allCases) { layer in
                            Button { Preferences.shared.layer=layer } label: {
                                if Preferences.shared.layer==layer { Label(layer.title,systemImage:"checkmark") } else { Text(layer.title) }
                            }
                        }
                    }
                    Divider()
                    Button("备份事件…") { Windows.shared.exportData() }
                    Button("导入事件…") { Windows.shared.importData() }
                    Divider()
                    Button("退出 Time Master") { NSApplication.shared.terminate(nil) }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                Button { Windows.shared.edit(nil) } label: { Image(systemName: "plus").frame(width: 24, height: 24) }.buttonStyle(.glass).accessibilityLabel("新建倒计时")
            }.padding(18)
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.red).padding() }
            if store.events.isEmpty {
                ContentUnavailableView("添加第一个倒计时", systemImage: "hourglass", description: Text("把重要的日子放在桌面。"))
                Button("添加倒计时") { Windows.shared.edit(nil) }.padding(.bottom)
            } else {
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(store.events.sorted { $0.end < $1.end }) { e in
                            HStack {
                                Button { Windows.shared.edit(e) } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "calendar").foregroundStyle(e.tint).frame(width: 30, height: 34).background(e.tint.opacity(0.1), in: .rect(cornerRadius: 10))
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(e.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                            Text(e.end.formatted(.dateTime.month().day().hour().minute())).font(.system(size: 10)).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing) {
                                            Text("\(e.remaining)").font(.system(size: 25, weight: .light)).monospacedDigit()
                                            Text(e.status).font(.system(size: 9)).foregroundStyle(.secondary)
                                        }
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Button { store.toggle(e) } label: { Image(systemName: e.visible ? "eye" : "eye.slash").foregroundStyle(.secondary) }.buttonStyle(.plain).help(e.visible ? "隐藏卡片" : "显示卡片")
                            }.padding(12)
                        }
                    }.padding(.horizontal, 6)
                }.frame(maxHeight: 360)
            }
            Divider().padding(.horizontal,18)
            VStack(alignment:.leading,spacing:10) {
                HStack {
                    Text("组合窗口").font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button { Windows.shared.editGroup() } label: { Label("新建组合",systemImage:"rectangle.stack.badge.plus").font(.system(size:11)) }.buttonStyle(.plain).disabled(store.events.count<2 || groups.error != nil).help("将至少两个事件放在同一个窗口")
                }
                if let error=groups.error { Text(error).font(.caption).foregroundStyle(.red) }
                if !groups.groups.isEmpty {
                    ScrollView {
                        VStack(spacing:12) {
                            ForEach(groups.groups) { g in
                                HStack {
                                    Button { Windows.shared.editGroup(g) } label: {
                                        HStack(spacing:10) { Image(systemName:"rectangle.stack").foregroundStyle(.indigo); VStack(alignment:.leading,spacing:4) { Text(g.title).font(.system(size:12,weight:.medium)).lineLimit(1); Text("\(g.members(in:store.events).count) 个事件 · \(g.style.title)").font(.system(size:9)).foregroundStyle(.secondary) }; Spacer() }
                                    }.buttonStyle(.plain)
                                    Button { groups.toggle(g) } label: { Image(systemName:g.visible ? "eye" : "eye.slash").foregroundStyle(.secondary) }.buttonStyle(.plain)
                                }
                            }
                        }
                    }.frame(maxHeight:150)
                }
            }.padding(18)
            Divider().padding(.horizontal,18)
            Toggle("桌面窗口", isOn: $store.showCards).toggleStyle(.switch).font(.system(size: 12)).padding(18)
                .onChange(of: store.showCards) { _, _ in Windows.shared.refresh() }
        }.frame(width: 340)
    }
}

@MainActor final class Windows: NSObject, NSWindowDelegate {
    static let shared = Windows()
    var panels: [UUID:NSPanel] = [:]
    var groupPanels:[UUID:NSPanel]=[:]
    var groupEditor:NSWindow?
    var editor: NSWindow?
    var settingsWindow: NSWindow?
    private var applyingGeometry = false
    var dragging = false
    func refresh() {
        let store = Store.shared
        let ids = Set(store.events.filter { $0.visible && store.showCards }.map(\.id))
        for id in Array(panels.keys) where !ids.contains(id) { panels.removeValue(forKey: id)?.close() }
        for (i,e) in store.events.enumerated() where ids.contains(e.id) && panels[e.id] == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0,y: 0,width: e.cardSize.width+28,height: e.cardSize.height+28), styleMask: [.borderless,.nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false; panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
            panel.isMovableByWindowBackground = false; panel.level = .normal
            panel.appearance = NSAppearance(named: .darkAqua)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = DraggableCardHost(id: e.id)
            panel.minSize = CGSize(width:308,height:168); panel.maxSize = CGSize(width:788,height:568)
            let frame = NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1440,height:900)
            var origin = NSPoint(x: e.x ?? frame.minX+32, y: e.y ?? max(frame.minY+20, frame.maxY-380-Double(i%2)*350))
            if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(NSRect(origin: origin, size: panel.frame.size)) }) { origin = NSPoint(x: frame.minX+32,y:frame.maxY-380) }
            panel.setFrameOrigin(origin); panel.delegate = self; panels[e.id] = panel; applyLayer(Preferences.shared.layer,to:panel); panel.orderFrontRegardless()
        }
        refreshGroups()
    }
    func applyLayer(_ mode:CardLayer,to panel:NSPanel) {
        panel.hidesOnDeactivate=false
        panel.isFloatingPanel = mode == .floating
        panel.level=mode.windowLevel
        panel.collectionBehavior=mode.windowBehavior
    }
    func applyLayers() {
        let mode=Preferences.shared.layer
        for panel in allPanels {
            applyLayer(mode,to:panel)
            if mode == .desktop { panel.orderBack(nil) } else { panel.orderFrontRegardless() }
        }
    }
    func windowDidMove(_ notification: Notification) {
        guard !dragging, !applyingGeometry, let window=notification.object as? NSPanel else { return }
        if let id=panels.first(where:{$0.value===window})?.key { Store.shared.position(id,window.frame.origin) }
        else if let id=groupPanels.first(where:{$0.value===window})?.key { GroupStore.shared.position(id,window.frame.origin) }
    }
    func applySize(_ event: Event) {
        guard !dragging, let panel=panels[event.id] else { return }
        let size=CGSize(width:event.cardSize.width+28,height:event.cardSize.height+28)
        guard panel.frame.size != size else { return }
        applyingGeometry=true
        let frame=CGRect(x:panel.frame.minX,y:panel.frame.maxY-size.height,width:size.width,height:size.height)
        panel.setFrame(frame,display:true)
        applyingGeometry=false
        Store.shared.commitGeometry(event.id,frame:frame)
    }
    func resizeCard(_ id:UUID,to size:CGSize) {
        guard var e=Store.shared.events.first(where:{$0.id==id}) else { return }
        let size=CardGeometry.clamp(size); e.cardWidth=size.width; e.cardHeight=size.height
        Store.shared.upsert(e)
    }
    func finishDrag(_ window:NSWindow,id:UUID,bypass:Bool) {
        let before=window.frame
        let prefs=Preferences.shared
        let neighbors=allPanels.filter { $0 !== window }.map { $0.frame } + (prefs.systemWidgets ? externalWidgetFrames() : [])
        let after = !bypass && prefs.snapping ? CardSnap.snapped(before,screens:NSScreen.screens.map(\.visibleFrame),neighbors:neighbors,threshold:prefs.distance,gap:prefs.gap) : before
        applyingGeometry=true
        window.setFrame(after,display:true)
        applyingGeometry=false
        if let host=window.contentView as? DraggableCardHost {
            host.interaction.release(displacement:CGSize(width:before.minX-after.minX,height:after.minY-before.minY))
        }
        if let host=window.contentView as? DraggableCardHost,host.isGroup { GroupStore.shared.commitGeometry(id,frame:after) }
        else { Store.shared.commitGeometry(id,frame:after) }
    }
    func settings(eventID:UUID? = nil) {
        if let w=settingsWindow, w.isVisible, eventID == nil { NSApp.activate(ignoringOtherApps:true); w.makeKeyAndOrderFront(nil); return }
        settingsWindow?.close()
        let w=NSWindow(contentRect:NSRect(x:0,y:0,width:940,height:640),styleMask:[.titled,.closable,.fullSizeContentView],backing:.buffered,defer:false)
        w.title="设置 · Time Master"; w.titlebarAppearsTransparent=true; w.isReleasedWhenClosed=false
        w.appearance=NSAppearance(named:.darkAqua)
        w.contentView=NSHostingView(rootView:SettingsView(selectedID:eventID ?? Store.shared.events.first?.id))
        w.center(); settingsWindow=w; NSApp.activate(ignoringOtherApps:true); w.makeKeyAndOrderFront(nil)
    }
    // Native widgets are hosted by system processes. Use only independently
    // exposed on-screen bounds; never snap to a full-desktop container.
    func externalWidgetFrames() -> [CGRect] {
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]],
              let top = NSScreen.screens.first?.frame.maxY else { return [] }
        return windows.compactMap { info in
            let owner = (info[kCGWindowOwnerName as String] as? String ?? "").lowercased()
            guard owner.contains("widget") || owner == "notificationcenter" || owner == "notification center" || owner == "chronod",
                  let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dictionary),
                  rect.width >= 64, rect.width <= 800, rect.height >= 64, rect.height <= 800,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { return nil }
            return CGRect(x: rect.minX, y: top-rect.maxY, width: rect.width, height: rect.height)
                .insetBy(dx: -CardSnap.margin, dy: -CardSnap.margin)
        }
    }
    func edit(_ item: Event?) {
        if let editor { editor.close(); self.editor = nil }
        let now = Date()
        let e = item ?? Event(title: "", start: now, end: Calendar.current.date(byAdding: .day,value: 7,to: now)!)
        let w = NSWindow(contentRect: NSRect(x:0,y:0,width:768,height:620),styleMask:[.titled,.closable,.fullSizeContentView],backing:.buffered,defer:false)
        w.title = "编辑倒计时 · Time Master"; w.titlebarAppearsTransparent = true; w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named:.darkAqua)
        w.contentView = NSHostingView(rootView: Editor(event:e,isNew:item == nil)); w.center(); editor=w
        NSApp.activate(ignoringOtherApps:true); w.makeKeyAndOrderFront(nil)
    }
    func closeEditor() { editor?.close(); editor=nil }
    func exportData() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Time-Master-backup.json"; NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url=panel.url else { return }
        do {
            if let message=GroupStore.shared.error { throw NSError(domain:"TimeMaster",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
            try JSONEncoder().encode(BackupDocument(events:Store.shared.events,groups:GroupStore.shared.groups)).write(to:url,options:.atomic)
        } catch { showError(error) }
    }
    func importData() {
        let panel=NSOpenPanel(); panel.allowsMultipleSelection=false; NSApp.activate(ignoringOtherApps:true)
        guard panel.runModal() == .OK, let url=panel.url else { return }
        do {
            if let message=GroupStore.shared.error { throw NSError(domain:"TimeMaster",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
            let document=try BackupDocument.read(Data(contentsOf:url))
            for var item in document.events { let size=item.cardSize; item.cardWidth=size.width; item.cardHeight=size.height; Store.shared.upsert(item) }
            for group in document.groups {
                if !GroupStore.shared.upsert(group) { throw NSError(domain:"TimeMaster",code:2,userInfo:[NSLocalizedDescriptionKey:GroupStore.shared.error ?? "无法保存组合"]) }
            }
        } catch { showError(error) }
    }
    func showError(_ error: Error) { let a=NSAlert(); a.messageText="操作未完成"; a.informativeText=error.localizedDescription; a.runModal() }
}
final class Delegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            Windows.shared.refresh()
            if CommandLine.arguments.contains("--groups") { Windows.shared.editGroup() }
            if CommandLine.arguments.contains("--settings") { Windows.shared.settings(eventID:Store.shared.events.first(where:{$0.visible})?.id) }
            if CommandLine.arguments.contains("--verify-ui") {
                try? await Task.sleep(for: .seconds(1))
                for panel in Windows.shared.panels.values {
                    guard let host = panel.contentView as? DraggableCardHost else { fatalError("Missing drag host") }
                    host.layoutSubtreeIfNeeded()
                    let e=Store.shared.events.first(where:{$0.id==host.eventID})!
                    assert(panel.frame.size == CGSize(width:e.cardSize.width+28,height:e.cardSize.height+28))
                    assert(host.hitTest(NSPoint(x: 100,y: 150)) === host, "Card body must route to native dragging")
                    assert(panel.appearance?.name == .darkAqua)
                }
                await NativeVerification.run()
                print("PASS: native card dimensions, dark appearance, drag hit-test routing; \(Windows.shared.panels.count) live panels")
                fflush(stdout)
                NSApp.terminate(nil)
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
@main struct TimeMasterApp: App {
    @NSApplicationDelegateAdaptor(Delegate.self) var delegate
    @StateObject var store = Store.shared
    var body: some Scene {
        MenuBarExtra { PanelMenu() } label: { Image(systemName:"hourglass"); Text(store.events.filter { $0.end > Date() }.min(by: {$0.end < $1.end}).map { "\($0.remaining)天" } ?? "Time Master") }.menuBarExtraStyle(.window)
        .commands { CommandGroup(after:.appInfo) { Button("设置…") { Windows.shared.settings() }.keyboardShortcut(",",modifiers:.command); Button("新建组合…") { Windows.shared.editGroup() }.keyboardShortcut("n",modifiers:[.command,.shift]) } }
    }
}
