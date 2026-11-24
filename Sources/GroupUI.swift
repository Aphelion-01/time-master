import SwiftUI

struct GroupSurface:View {
    let group:EventGroup
    let events:[Event]
    let size:CGSize
    var now:Date = .now
    var hover=false
    var preview=false
    var onEdit:()->Void = {}
    var onStyle:(GroupViewStyle)->Void = { _ in }
    var onHide:()->Void = {}
    @ObservedObject var preferences=Preferences.shared
    var members:[Event] { group.members(in:events,now:now) }
    var body:some View {
        let visibleMembers=members
        let sharedAxis=SharedTimeAxis(events:visibleMembers,now:now)
        VStack(alignment:.leading,spacing:0) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:7) {
                    Text(group.title).font(.system(size:size.width>=700 ? 24 : 20,weight:.semibold)).lineLimit(1)
                    Text("\(visibleMembers.count) 个时间节点").font(.system(size:11)).foregroundStyle(.secondary)
                }
                Spacer()
                if !preview {
                    Menu {
                        Button("编辑组合",action:onEdit)
                        ForEach(GroupViewStyle.allCases) { style in Button(style.title) { onStyle(style) } }
                        Divider()
                        Button("隐藏组合窗口",action:onHide)
                    } label: { Image(systemName:"ellipsis").frame(width:28,height:28) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("组合操作")
                }
            }.padding(.horizontal,26).padding(.top,24).padding(.bottom,20)
            Divider().overlay(.white.opacity(0.05)).padding(.horizontal,26)
            if visibleMembers.isEmpty {
                VStack(spacing:12) { Image(systemName:"rectangle.stack.badge.plus").font(.system(size:25)).foregroundStyle(.secondary); Text("为这个组合添加事件").font(.system(size:13)); if !preview { Button("选择事件",action:onEdit).buttonStyle(.bordered) } }.frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                ScrollView {
                    VStack(alignment:.leading,spacing:18) {
                        if group.style == .timeline { axisHeader(events:visibleMembers,axis:sharedAxis) }
                        if group.style == .tiles {
                            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:14),count:GroupGeometry.columns(width:size.width)),spacing:14) {
                                ForEach(visibleMembers) { e in eventButton(e) { tile(e) } }
                            }
                        } else {
                            LazyVStack(spacing:20) { ForEach(visibleMembers) { e in eventButton(e) { row(e,axis:sharedAxis) } } }
                        }
                    }.padding(.horizontal,26).padding(.vertical,22)
                }.scrollIndicators(.automatic)
            }
            HStack {
                Text(group.style.detail).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength:10)
                if hover && !preview { Text("拖动标题移动").font(.system(size:9)).foregroundStyle(.tertiary) }
            }.padding(.horizontal,26).padding(.top,9).padding(.bottom,19)
        }.frame(width:size.width,height:size.height,alignment:.topLeading)
            .background { RoundedRectangle(cornerRadius:26).fill(.black.opacity(preferences.depth)) }
            .glassEffect(.regular,in:.rect(cornerRadius:26))
            .overlay(alignment:.bottomTrailing) {
                if !preview { Image(systemName:"arrow.up.left.and.arrow.down.right").font(.system(size:10)).foregroundStyle(.white.opacity(hover ? 0.65 : 0.3)).padding(10).allowsHitTesting(false) }
            }
            .foregroundStyle(.white).environment(\.colorScheme,.dark)
    }
    func eventButton<Content:View>(_ event:Event,@ViewBuilder label:()->Content) -> some View {
        Button { if !preview { Windows.shared.edit(event) } } label: { label().frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle()) }
            .buttonStyle(.plain).allowsHitTesting(!preview).help("编辑 \(event.title)；\(event.end.formatted())")
    }
    func fraction(_ e:Event) -> Double { e.end>e.start ? min(1,max(0,e.end.timeIntervalSince(now)/e.end.timeIntervalSince(e.start))) : 0 }
    func axisHeader(events:[Event],axis:SharedTimeAxis) -> some View {
        HStack { Text("今天"); Spacer(); Text(events.allSatisfy {$0.end<=now} ? "全部已到期" : axis.end.formatted(.dateTime.month().day())) }.font(.system(size:10)).foregroundStyle(.secondary)
    }
    func row(_ e:Event,axis:SharedTimeAxis) -> some View {
        VStack(alignment:.leading,spacing:11) {
            HStack(alignment:.center,spacing:16) {
                VStack(alignment:.leading,spacing:7) {
                    HStack(spacing:8) { Circle().fill(e.tint).frame(width:6,height:6); Text(e.title).font(.system(size:14,weight:.medium)).lineLimit(1) }
                    Text(e.end.formatted(.dateTime.month().day().hour().minute())).font(.system(size:10)).foregroundStyle(.secondary)
                }
                Spacer(minLength:0)
                HStack(alignment:.firstTextBaseline,spacing:5) { Text("\(e.remaining)").font(.system(size:31,weight:.light)).monospacedDigit(); Text(e.status).font(.system(size:10)).foregroundStyle(.secondary) }.lineLimit(1)
            }
            if group.style == .lanes {
                RemainderRail(fraction:fraction(e),tint:e.tint).frame(height:8)
                HStack { Text("\(e.start.formatted(.dateTime.month().day())) 起算"); Spacer(); Text("周期剩余 \(fraction(e).formatted(.percent.precision(.fractionLength(1))))") }.font(.system(size:9)).foregroundStyle(.secondary)
            } else {
                GeometryReader { g in
                    let f=axis.fraction(for:e.end)
                    ZStack(alignment:.leading) {
                        Capsule().fill(.white.opacity(0.09)).frame(height:2)
                        Capsule().fill(e.tint.opacity(0.5)).frame(width:max(2,g.size.width*f),height:2)
                        Circle().fill(e.end>now ? e.tint : .white.opacity(0.3)).frame(width:8,height:8).offset(x:min(g.size.width-8,max(0,g.size.width*f-4)))
                    }.frame(height:12)
                }.frame(height:12)
            }
        }
    }
    func tile(_ e:Event) -> some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:7) { Circle().fill(e.tint).frame(width:6,height:6); Text(e.title).font(.system(size:13,weight:.medium)).lineLimit(1) }
            HStack(alignment:.center) {
                VStack(alignment:.leading,spacing:1) { Text("\(e.remaining)").font(.system(size:42,weight:.light)).monospacedDigit(); Text(e.status).font(.system(size:10)).foregroundStyle(.secondary) }
                Spacer(minLength:4)
                ZStack {
                    Circle().stroke(.white.opacity(0.1),lineWidth:4)
                    Circle().trim(from:0,to:fraction(e)).stroke(e.tint,style:StrokeStyle(lineWidth:4,lineCap:.round)).rotationEffect(.degrees(-90))
                    Text(fraction(e).formatted(.percent.precision(.fractionLength(0)))).font(.system(size:10)).monospacedDigit()
                }.frame(width:47,height:47).padding(3)
            }
            Text(e.end.formatted(.dateTime.month().day().hour().minute())).font(.system(size:9)).foregroundStyle(.secondary).lineLimit(1)
        }.padding(16).background(.white.opacity(0.035),in:.rect(cornerRadius:14))
    }
}
struct RemainderRail:View {
    let fraction:Double
    let tint:Color
    var body:some View {
        Canvas { context,size in
            let count=16, step=size.width/Double(count), boundary=(1-fraction)*size.width
            for i in 0..<count {
                let rect=CGRect(x:Double(i)*step,y:0,width:max(1,step-3),height:size.height)
                let path=Path(roundedRect:rect,cornerRadius:2)
                context.fill(path,with:.color(.white.opacity(0.13)))
                if rect.maxX>boundary {
                    var colored=context
                    colored.clip(to:Path(CGRect(x:max(rect.minX,boundary),y:0,width:rect.maxX-max(rect.minX,boundary),height:size.height)))
                    colored.fill(path,with:.color(tint))
                }
            }
        }.accessibilityLabel("周期剩余 \(Int(fraction*100))%")
    }
}
