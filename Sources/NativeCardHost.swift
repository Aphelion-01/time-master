import SwiftUI
import AppKit

@MainActor final class DraggableCardHost: NSHostingView<GlassCard> {
    let eventID: UUID
    let isGroup:Bool
    let interaction: CardInteraction
    private var initialFrame: CGRect?
    private var initialMouse: CGPoint?
    private var previousMouse: CGPoint = .zero
    private var previousTime: TimeInterval = 0
    private var velocity = CGVector.zero
    private var resizing = false
    required init(rootView: GlassCard) {
        eventID=rootView.id; isGroup=rootView.isGroup; interaction=rootView.interaction
        super.init(rootView:rootView)
        wantsLayer=true
    }
    convenience init(id:UUID,isGroup:Bool = false) { self.init(rootView:GlassCard(interaction:CardInteraction(),id:id,isGroup:isGroup)) }
    @available(*,unavailable) required init?(coder:NSCoder) { fatalError() }
    private func localPoint(_ point:NSPoint) -> NSPoint {
        let p=convert(point,from:superview)
        return NSPoint(x:p.x,y:isFlipped ? p.y : bounds.height-p.y)
    }
    private func isMenu(_ p:NSPoint) -> Bool { p.x >= bounds.width-78 && p.x <= bounds.width-24 && p.y >= 28 && p.y <= 67 }
    private func isResize(_ p:NSPoint) -> Bool { p.x >= bounds.width-42 && p.y >= bounds.height-42 }
    override func hitTest(_ point:NSPoint) -> NSView? {
        guard let hit=super.hitTest(point) else { return nil }
        let p=localPoint(point)
        return isMenu(p) || (isGroup && p.y>110 && !isResize(p)) ? hit : self
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(NSRect(x:bounds.width-42,y:isFlipped ? bounds.height-42 : 0,width:28,height:28),cursor:.frameResize(position:.bottomRight,directions:.all))
    }
    override func mouseDown(with event:NSEvent) {
        guard let window else { return }
        if Preferences.shared.layer == .normal { window.orderFront(nil) }
        let local=convert(event.locationInWindow,from:nil)
        let p=NSPoint(x:local.x,y:isFlipped ? local.y : bounds.height-local.y)
        if isMenu(p) { super.mouseDown(with:event); return }
        if isGroup && p.y>110 && !isResize(p) { super.mouseDown(with:event); return }
        resizing=isResize(p)
        if event.clickCount == 2 && !resizing { openEditor(); return }
        initialFrame=window.frame; initialMouse=NSEvent.mouseLocation
        previousMouse=initialMouse!; previousTime=event.timestamp; velocity = .zero
        Windows.shared.dragging=true
        interaction.begin()
        if resizing { interaction.neutral() }
    }
    override func mouseDragged(with event:NSEvent) {
        guard let window,let frame=initialFrame,let origin=initialMouse else { super.mouseDragged(with:event); return }
        let current=NSEvent.mouseLocation
        let dt=max(1.0/120,min(0.1,event.timestamp-previousTime))
        let vx=(current.x-previousMouse.x)/dt, vy=(current.y-previousMouse.y)/dt
        velocity=CGVector(dx:velocity.dx*0.7+vx*0.3,dy:velocity.dy*0.7+vy*0.3)
        previousMouse=current; previousTime=event.timestamp
        let delta=CGSize(width:current.x-origin.x,height:current.y-origin.y)
        if resizing {
            window.setFrame(isGroup ? GroupGeometry.resize(frame,translation:delta) : CardGeometry.resize(frame,translation:delta),display:true)
        } else {
            window.setFrameOrigin(NSPoint(x:frame.minX+delta.width,y:frame.minY+delta.height))
            interaction.follow(vx:velocity.dx,vy:velocity.dy)
        }
    }
    override func mouseUp(with event:NSEvent) {
        guard let window,initialFrame != nil else { super.mouseUp(with:event); return }
        let wasResizing=resizing
        initialFrame=nil; initialMouse=nil; resizing=false
        Windows.shared.finishDrag(window,id:eventID,bypass:wasResizing || event.modifierFlags.contains(.shift))
        Windows.shared.dragging=false
    }
    override func rightMouseDown(with event:NSEvent) {
        let menu=NSMenu()
        for (title,action) in [(isGroup ? "编辑组合" : "编辑倒计时",#selector(openEditor)),("设置…",#selector(openSettings)),("恢复标准大小",#selector(resetSize)),(isGroup ? "隐藏组合" : "隐藏卡片",#selector(hideCard))] {
            let item=NSMenuItem(title:title,action:action,keyEquivalent:""); item.target=self; menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu,with:event,for:self)
    }
    @objc func openEditor() { if isGroup { if let g=GroupStore.shared.groups.first(where:{$0.id==eventID}) { Windows.shared.editGroup(g) }; return }; if let e=Store.shared.events.first(where:{$0.id==eventID}) { Windows.shared.edit(e) } }
    @objc func openSettings() { Windows.shared.settings(eventID:isGroup ? nil : eventID) }
    @objc func resetSize() { if isGroup { Windows.shared.resetGroupSize(eventID) } else { Windows.shared.resizeCard(eventID,to:CardLayout.standard.size) } }
    @objc func hideCard() { if isGroup { if let g=GroupStore.shared.groups.first(where:{$0.id==eventID}) { GroupStore.shared.toggle(g) }; return }; if let e=Store.shared.events.first(where:{$0.id==eventID}) { Store.shared.toggle(e) } }
}
