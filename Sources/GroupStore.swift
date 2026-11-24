import SwiftUI
import AppKit

@MainActor final class GroupStore:ObservableObject {
    static let shared=GroupStore()
    @Published var groups:[EventGroup]=[]
    @Published var error:String?
    let url:URL
    init(url overrideURL:URL? = nil) {
        url=overrideURL ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("TimeMaster/groups.json")
        if FileManager.default.fileExists(atPath:url.path) {
            do {
                let saved=try JSONDecoder().decode([EventGroup].self,from:Data(contentsOf:url))
                guard Set(saved.map(\.id)).count==saved.count else { throw CocoaError(.fileReadCorruptFile) }
                groups=saved.map { g in var g=g; g.eventIDs=g.uniqueIDs; let size=g.size; g.width=size.width; g.height=size.height; return g }
            } catch { self.error="无法读取组合，原文件已保留：\(error.localizedDescription)" }
        }
    }
    @discardableResult func save() -> Bool {
        guard error==nil else { return false }
        do {
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(groups).write(to:url,options:.atomic)
            return true
        } catch { self.error="组合保存失败：\(error.localizedDescription)"; return false }
    }
    @discardableResult func upsert(_ group:EventGroup) -> Bool {
        guard error==nil else { return false }
        var group=group; group.eventIDs=group.uniqueIDs
        let size=group.size; group.width=size.width; group.height=size.height
        let previous=groups
        if let i=groups.firstIndex(where:{$0.id==group.id}) { groups[i]=group } else { groups.append(group) }
        let ok=save()
        if !ok { groups=previous }
        Windows.shared.refreshGroups(); return ok
    }
    func toggle(_ group:EventGroup) { var g=group; g.visible.toggle(); upsert(g) }
    func setStyle(_ style:GroupViewStyle,for group:EventGroup) { var g=group; g.style=style; upsert(g) }
    func remove(_ id:UUID,restoreMembers:Bool) {
        guard error==nil,let group=groups.first(where:{$0.id==id}) else { return }
        let previous=groups
        groups.removeAll { $0.id==id }
        guard save() else { groups=previous; return }
        if restoreMembers { for var e in group.members(in:Store.shared.events) { e.visible=true; Store.shared.upsert(e) } }
        Windows.shared.refreshGroups()
    }
    func prune(_ eventID:UUID) {
        guard error==nil else { return }
        var changed=false
        for i in groups.indices where groups[i].eventIDs.contains(eventID) { groups[i].eventIDs.removeAll { $0==eventID }; changed=true }
        if changed { save(); Windows.shared.refreshGroups() }
    }
    func commitGeometry(_ id:UUID,frame:CGRect) {
        guard let i=groups.firstIndex(where:{$0.id==id}) else { return }
        let size=GroupGeometry.clamp(CGSize(width:frame.width-28,height:frame.height-28))
        groups[i].x=frame.minX; groups[i].y=frame.minY; groups[i].width=size.width; groups[i].height=size.height
        save()
    }
    func position(_ id:UUID,_ point:CGPoint) {
        guard let i=groups.firstIndex(where:{$0.id==id}) else { return }
        groups[i].x=point.x; groups[i].y=point.y; save()
    }
}

extension Windows {
    var allPanels:[NSPanel] { Array(panels.values)+Array(groupPanels.values) }
    func refreshGroups() {
        let store=GroupStore.shared
        let ids=Set(store.groups.filter { $0.visible && Store.shared.showCards }.map(\.id))
        for id in Array(groupPanels.keys) where !ids.contains(id) { groupPanels.removeValue(forKey:id)?.close() }
        for group in store.groups where ids.contains(group.id) {
            if let panel=groupPanels[group.id] {
                let desired=CGSize(width:group.size.width+28,height:group.size.height+28)
                if panel.frame.size != desired && !dragging {
                    let old=dragging; dragging=true
                    panel.setFrame(CGRect(x:panel.frame.minX,y:panel.frame.maxY-desired.height,width:desired.width,height:desired.height),display:true)
                    dragging=old; store.commitGeometry(group.id,frame:panel.frame)
                }
                continue
            }
            let panel=NSPanel(contentRect:CGRect(origin:.zero,size:CGSize(width:group.size.width+28,height:group.size.height+28)),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            panel.isReleasedWhenClosed=false; panel.backgroundColor = .clear; panel.isOpaque=false; panel.hasShadow=false
            panel.isMovableByWindowBackground=false; panel.appearance=NSAppearance(named:.darkAqua)
            panel.contentView=DraggableCardHost(id:group.id,isGroup:true)
            panel.minSize=CGSize(width:408,height:288); panel.maxSize=CGSize(width:988,height:748)
            let screen=NSScreen.main?.visibleFrame ?? CGRect(x:0,y:0,width:1440,height:900)
            var origin=CGPoint(x:group.x ?? screen.midX-group.size.width/2,y:group.y ?? screen.midY-group.size.height/2)
            if !NSScreen.screens.contains(where:{$0.visibleFrame.intersects(CGRect(origin:origin,size:panel.frame.size))}) { origin=CGPoint(x:screen.minX+30,y:screen.maxY-panel.frame.height-20) }
            panel.setFrameOrigin(origin); panel.delegate=self; groupPanels[group.id]=panel
            applyLayer(Preferences.shared.layer,to:panel); panel.orderFrontRegardless()
        }
    }
    func editGroup(_ item:EventGroup? = nil) {
        groupEditor?.close()
        let group=item ?? EventGroup(title:"我的组合",eventIDs:[])
        let w=NSWindow(contentRect:NSRect(x:0,y:0,width:820,height:660),styleMask:[.titled,.closable,.fullSizeContentView],backing:.buffered,defer:false)
        w.title=item==nil ? "新建组合 · Time Master" : "编辑组合 · Time Master"
        w.titlebarAppearsTransparent=true; w.isReleasedWhenClosed=false; w.appearance=NSAppearance(named:.darkAqua)
        w.contentView=NSHostingView(rootView:GroupEditor(group:group,isNew:item==nil))
        w.center(); groupEditor=w; NSApp.activate(ignoringOtherApps:true); w.makeKeyAndOrderFront(nil)
    }
    func closeGroupEditor() { groupEditor?.close(); groupEditor=nil }
    func resetGroupSize(_ id:UUID) {
        if var group=GroupStore.shared.groups.first(where:{$0.id==id}) { group.width=560; group.height=420; GroupStore.shared.upsert(group) }
    }
}
