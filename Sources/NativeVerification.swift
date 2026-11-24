import SwiftUI
import AppKit

@MainActor enum NativeVerification {
    static func run() async {
        let manager=Windows.shared
        let wasDragging=manager.dragging
        manager.dragging=true
        defer { manager.dragging=wasDragging }
        var sample=Store.shared.events.first ?? Event(title:"界面验证",start:Date().addingTimeInterval(-23*86400),end:Date().addingTimeInterval(19*86400))
        sample.style = .dots
        let args=CommandLine.arguments
        let directory:URL? = args.firstIndex(of:"--snapshot-dir").flatMap { i in i+1 < args.count ? URL(fileURLWithPath:args[i+1]) : nil }
        if let directory { try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true) }
        if let panel=manager.panels.values.first,let host=panel.contentView as? DraggableCardHost {
            let saved=panel.frame
            let originalMode=Preferences.shared.layer
            for mode in CardLayer.allCases {
                manager.applyLayer(mode,to:panel)
                assert(panel.level==mode.windowLevel)
                assert(panel.collectionBehavior==mode.windowBehavior)
                assert(!panel.hidesOnDeactivate)
                assert(panel.frame==saved)
            }
            manager.applyLayer(originalMode,to:panel)
            print("PASS: three native layer levels/behaviors; geometry and current preference preserved")
            for layout in CardLayout.allCases {
                panel.setFrame(CGRect(origin:saved.origin,size:CGSize(width:layout.size.width+28,height:layout.size.height+28)),display:true)
                host.layoutSubtreeIfNeeded()
                assert(CardLayout.resolve(CGSize(width:host.bounds.width-28,height:host.bounds.height-28))==layout)
                assert(host.hitTest(NSPoint(x:100,y:80)) === host)
            }
            panel.setFrame(saved,display:true)
        }
        for layout in CardLayout.allCases {
            await render(CardSurface(event:sample,size:layout.size,preview:true),size:layout.size,to:directory?.appendingPathComponent("卡片-\(layout.rawValue)-原生渲染.png"))
        }
        await render(SettingsView(selectedID:Store.shared.events.first?.id),size:CGSize(width:940,height:640),to:directory?.appendingPathComponent("设置-原生渲染.png"))
        await render(Editor(event:sample,isNew:false),size:CGSize(width:768,height:620),to:directory?.appendingPathComponent("事件编辑-原生渲染.png"))
        await verifyGroups(directory:directory)
        print("PASS: four live layout sizes and drag hit regions; native settings and editor rendered")
    }
    static func verifyGroups(directory:URL?) async {
        let manager=Windows.shared
        let shared=GroupStore.shared
        let saved=shared.groups
        let now=Date()
        var events=Array(Store.shared.events.prefix(4))
        if events.count<2 {
            events=[Event(title:"考试",start:now.addingTimeInterval(-23*86400),end:now.addingTimeInterval(19*86400)),Event(title:"截止日期",start:now,end:now.addingTimeInterval(37*86400),color:1)]
        }
        var group=EventGroup(title:"考试安排",eventIDs:events.map(\.id))
        let testDirectory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:testDirectory) }
        let testURL=testDirectory.appendingPathComponent("groups.json")
        let isolated=GroupStore(url:testURL)
        isolated.groups=[group]; assert(isolated.save())
        assert(GroupStore(url:testURL).groups==[group])
        isolated.commitGeometry(group.id,frame:CGRect(x:45,y:90,width:668,height:488))
        assert(GroupStore(url:testURL).groups[0].size==CGSize(width:640,height:460))
        let sourceEvents=Store.shared.events
        isolated.remove(group.id,restoreMembers:false)
        assert(Store.shared.events==sourceEvents && GroupStore(url:testURL).groups.isEmpty)
        try! Data("invalid".utf8).write(to:testURL)
        let invalid=GroupStore(url:testURL)
        assert(invalid.error != nil && !invalid.save() && (try! Data(contentsOf:testURL))==Data("invalid".utf8))
        print("PASS: isolated group persistence/geometry, dissolving preserves events, corrupt file is not overwritten")
        shared.groups.append(group)
        manager.refreshGroups()
        defer { shared.groups=saved; manager.refreshGroups() }
        guard let panel=manager.groupPanels[group.id],let host=panel.contentView as? DraggableCardHost else { fatalError("Missing native combination panel") }
        assert(host.isGroup && host.eventID==group.id)
        assert(host.hitTest(NSPoint(x:100,y:60)) === host)
        for mode in CardLayer.allCases { manager.applyLayer(mode,to:panel); assert(panel.level==mode.windowLevel) }
        manager.applyLayer(Preferences.shared.layer,to:panel)
        for size in [CGSize(width:380,height:260),CGSize(width:560,height:420),CGSize(width:840,height:600)] {
            panel.setFrame(CGRect(origin:panel.frame.origin,size:CGSize(width:size.width+28,height:size.height+28)),display:true)
            host.layoutSubtreeIfNeeded(); assert(host.bounds.width==size.width+28)
        }
        for style in GroupViewStyle.allCases {
            group.style=style
            let size=style == .tiles ? CGSize(width:700,height:440) : CGSize(width:560,height:420)
            await render(GroupSurface(group:group,events:events,size:size,preview:true),size:size,to:directory?.appendingPathComponent("组合-\(style.title)-原生渲染.png"))
        }
        group.style = .lanes
        await render(GroupEditor(group:group,isNew:false),size:CGSize(width:860,height:680),to:directory?.appendingPathComponent("组合编辑-原生渲染.png"))
        print("PASS: real combined panel, header drag routing, three layers, responsive sizes and three graph views rendered")
    }
    static func render<V:View>(_ view:V,size:CGSize,to url:URL?) async {
        let host=NSHostingView(rootView:view.environment(\.colorScheme,.dark))
        let window=NSWindow(contentRect:CGRect(origin:.zero,size:size),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false; window.appearance=NSAppearance(named:.darkAqua)
        window.contentView=host; window.setContentSize(size); window.center(); window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(for:.milliseconds(250))
        assert(host.bounds.width >= size.width-1 && host.bounds.height >= size.height-1)
        if let url,let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) {
            host.cacheDisplay(in:host.bounds,to:bitmap)
            guard let data=bitmap.representation(using:.png,properties:[:]) else { fatalError("PNG encoding failed") }
            do { try data.write(to:url,options:.atomic) } catch { fatalError("Snapshot export failed: \(error)") }
        }
        window.close()
    }
}
