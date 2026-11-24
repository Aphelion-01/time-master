import SwiftUI

struct GlassCard: View {
    @ObservedObject var store=Store.shared
    @ObservedObject var groups=GroupStore.shared
    @ObservedObject var preferences=Preferences.shared
    @ObservedObject var interaction:CardInteraction
    let id:UUID
    var isGroup=false
    @State private var hover=false
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var body:some View {
        GeometryReader { proxy in
            let size=CGSize(width:max(1,proxy.size.width-28),height:max(1,proxy.size.height-28))
            TimelineView(.periodic(from:.now,by:30)) { clock in
                ZStack {
                    if isGroup,let g=groups.groups.first(where:{$0.id==id}) {
                        GroupSurface(group:g,events:store.events,size:size,now:clock.date,hover:hover,onEdit:{Windows.shared.editGroup(g)},onStyle:{groups.setStyle($0,for:g)},onHide:{groups.toggle(g)})
                    } else if !isGroup,let e=store.events.first(where:{$0.id==id}) {
                        CardSurface(event:e,size:size,hover:hover,onEdit:{Windows.shared.edit(e)},onStyle:{store.setStyle($0,for:e)},onHide:{store.toggle(e)})
                    }
                }
                .rotationEffect(.degrees(reduceMotion || !preferences.motion ? 0 : interaction.angle*min(1,min(380/size.width,280/size.height))))
                .scaleEffect(x:reduceMotion || !preferences.motion ? 1 : interaction.sx,y:reduceMotion || !preferences.motion ? 1 : interaction.sy)
                .offset(x:reduceMotion || !preferences.motion ? 0 : interaction.dx,y:reduceMotion || !preferences.motion ? 0 : interaction.dy)
                .padding(14).onHover { hover=$0 }
            }
        }.environment(\.colorScheme,.dark)
    }
}

struct CardSurface: View {
    var event: Event
    var size: CGSize
    var hover = false
    var preview = false
    var onEdit: () -> Void = {}
    var onStyle: (DisplayStyle) -> Void = { _ in }
    var onHide: () -> Void = {}
    @ObservedObject var preferences = Preferences.shared
    var layout: CardLayout { CardLayout.resolve(size) }
    var body: some View {
        ZStack(alignment:.topLeading) {
            content.padding(layout == .compact ? 18 : 26)
            if !preview {
                Menu {
                    Button("编辑倒计时",action:onEdit)
                    ForEach(DisplayStyle.allCases,id:\.self) { style in Button(style.rawValue) { onStyle(style) } }
                    Divider()
                    Button("设置…") { Windows.shared.settings() }
                    Button("隐藏卡片",action:onHide)
                } label: { Image(systemName:"ellipsis").font(.system(size:14)).frame(width:28,height:28) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .opacity(hover ? 1 : 0).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topTrailing).padding(.top,17).padding(.trailing,20)
                .accessibilityLabel("卡片操作")
                Image(systemName:"arrow.up.left.and.arrow.down.right")
                    .font(.system(size:10,weight:.medium)).foregroundStyle(.white.opacity(hover ? 0.65 : 0.3))
                    .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.bottomTrailing).padding(10)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }.frame(width:size.width,height:size.height)
            .background { RoundedRectangle(cornerRadius:layout == .compact ? 22 : 26).fill(.black.opacity(preferences.depth)) }
            .glassEffect(.regular,in:.rect(cornerRadius:layout == .compact ? 22 : 26))
            .foregroundStyle(.white)
            .environment(\.colorScheme,.dark)
    }
    @ViewBuilder var content: some View {
        switch layout {
        case .compact:
            HStack(alignment:.center,spacing:14) {
                VStack(alignment:.leading,spacing:10) {
                    name(font:15)
                    date.font(.system(size:10)).lineLimit(1)
                    Text("\(event.totalDays) 天周期").font(.system(size:9)).foregroundStyle(.secondary)
                }
                Spacer(minLength:0)
                VStack(alignment:.trailing,spacing:0) {
                    Text("\(event.remaining)").font(.system(size:min(58,size.height*0.34),weight:.light)).monospacedDigit()
                    Text(event.status).font(.system(size:10)).foregroundStyle(.secondary)
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        case .standard:
            VStack(alignment:.leading,spacing:0) {
                name(font:18)
                date.font(.system(size:12)).padding(.top,12)
                Spacer(minLength:10)
                HStack(alignment:.center,spacing:14) {
                    number(font:min(75,size.height*0.24))
                    Spacer(minLength:0)
                    chart.frame(width:min(154,(size.width-70)*0.46),height:min(166,max(82,size.height-160)))
                }
                Spacer(minLength:12)
                footer
            }
        case .wide:
            VStack(alignment:.leading,spacing:16) {
                HStack { name(font:17); Spacer(); date.font(.system(size:11)).padding(.trailing,35) }
                HStack(spacing:28) {
                    HStack(alignment:.firstTextBaseline,spacing:10) {
                        Text("\(event.remaining)").font(.system(size:68,weight:.light)).monospacedDigit()
                        Text(event.status).font(.system(size:12)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength:0)
                    chart.frame(width:max(200,size.width*0.45),height:max(74,size.height-130))
                }.frame(maxHeight:.infinity)
                footer
            }
        case .expanded:
            VStack(alignment:.leading,spacing:16) {
                HStack { name(font:22); Spacer(); date.font(.system(size:12)).padding(.trailing,35) }
                HStack(spacing:30) {
                    number(font:min(112,size.width*0.19))
                    Spacer(minLength:0)
                    chart.frame(width:max(170,min(280,size.width*0.42)),height:max(140,size.height-220))
                }.frame(maxHeight:.infinity)
                Divider().overlay(.white.opacity(0.08))
                HStack {
                    VStack(alignment:.leading,spacing:7) { Text("起算").foregroundStyle(.secondary); Text(event.start.formatted(.dateTime.year().month().day())) }
                    Spacer()
                    VStack(alignment:.trailing,spacing:7) { Text("总周期").foregroundStyle(.secondary); Text("\(event.totalDays) 天") }
                }.font(.system(size:12))
            }
        }
    }
    func name(font:CGFloat) -> some View {
        HStack(spacing:10) { Circle().fill(event.tint).frame(width:7,height:7); Text(event.title).font(.system(size:font,weight:.semibold)).lineLimit(1) }
            .padding(.trailing,layout == .wide || layout == .expanded ? 0 : 30)
    }
    var date: some View { Text(event.end.formatted(.dateTime.month().day().hour().minute().locale(Locale(identifier:"zh_CN")))).foregroundStyle(.secondary) }
    func number(font:CGFloat) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text("\(event.remaining)").font(.system(size:font,weight:.light)).monospacedDigit().minimumScaleFactor(0.55).lineLimit(1)
            Text(event.status).font(.system(size:layout == .expanded ? 16 : 14)).foregroundStyle(.secondary)
        }
    }
    var footer: some View { Text("\(event.start.formatted(.dateTime.month(.twoDigits).day(.twoDigits))) 起算 · 总计 \(event.totalDays) 天").font(.system(size:10.5)).foregroundStyle(.secondary) }
    @ViewBuilder var chart: some View {
        switch event.style {
        case .dots: DayDots(event:event,columns:layout == .wide ? 14 : 7)
        case .ring: RemainingRing(event:event)
        case .timeline: TimeScale(event:event)
        }
    }
}
struct DayDots: View {
    let event: Event
    var columns = 7
    var body: some View {
        let total=event.totalDays, shown=min(total,84), left=min(total,event.remaining)
        VStack(alignment:.leading,spacing:10) {
            Canvas { context,size in
                let rows=Int(ceil(Double(shown)/Double(columns)))
                let step=min(size.width/CGFloat(columns),size.height/CGFloat(rows))
                let diameter=min(14,step*0.57)
                for i in 0..<shown {
                    let p=CGPoint(x:(CGFloat(i%columns)+0.5)*size.width/CGFloat(columns),y:(CGFloat(i/columns)+0.5)*size.height/CGFloat(rows))
                    let path=Path(ellipseIn:CGRect(x:p.x-diameter/2,y:p.y-diameter/2,width:diameter,height:diameter))
                    let filled=total <= 84 ? i >= total-left : Double(i)/Double(shown) >= 1-event.ratio
                    if filled { context.fill(path,with:.color(event.tint)) }
                    else { context.stroke(path,with:.color(.white.opacity(0.38)),lineWidth:1) }
                }
            }
            Text(total <= 84 ? "一格一天" : "全周期比例 · \(shown) 格").font(.system(size:10)).foregroundStyle(.secondary)
        }.accessibilityElement(children:.ignore).accessibilityLabel("剩余 \(left) 天，总计 \(total) 天")
    }
}
struct RemainingRing: View {
    let event: Event
    var body: some View {
        GeometryReader { g in
            let d=min(g.size.width,g.size.height), stroke=max(7,min(12,d*0.078))
            ZStack {
                Circle().inset(by:stroke/2).stroke(.white.opacity(0.13),lineWidth:stroke)
                Circle().inset(by:stroke/2).trim(from:0,to:event.ratio).stroke(event.tint,style:StrokeStyle(lineWidth:stroke,lineCap:.round)).rotationEffect(.degrees(-90))
                VStack(spacing:4) {
                    Text(event.ratio,format:.percent.precision(.fractionLength(1))).font(.system(size:max(14,d*0.15),weight:.medium)).monospacedDigit()
                    Text("剩余").font(.system(size:max(9,d*0.07))).foregroundStyle(.secondary)
                }
            }.frame(width:d,height:d).frame(maxWidth:.infinity,maxHeight:.infinity)
        }.accessibilityLabel("周期剩余 \(Int(event.ratio*100))%")
    }
}
struct TimeScale: View {
    let event: Event
    var body: some View {
        GeometryReader { g in
            let elapsed=1-event.ratio, y=max(32,g.size.height*0.42)
            ZStack(alignment:.topLeading) {
                Text("今天").font(.system(size:10)).foregroundStyle(.secondary).position(x:min(g.size.width-14,max(14,g.size.width*elapsed)),y:7)
                Path { p in p.move(to:CGPoint(x:g.size.width*elapsed,y:21)); p.addLine(to:CGPoint(x:g.size.width*elapsed,y:y-5)) }.stroke(.white.opacity(0.6),lineWidth:1)
                Canvas { context,size in
                    let count=min(84,event.totalDays), step=size.width/CGFloat(count)
                    for i in 0..<count {
                        let rect=CGRect(x:CGFloat(i)*step,y:0,width:max(1,step-3),height:14)
                        let color=Double(i)/Double(count) >= elapsed ? event.tint : Color.white.opacity(0.28)
                        context.fill(Path(roundedRect:rect,cornerRadius:2.5),with:.color(color))
                    }
                }.frame(height:14).offset(y:y)
                HStack { Text(event.start.formatted(.dateTime.month(.twoDigits).day(.twoDigits))); Spacer(); Text(event.end.formatted(.dateTime.month(.twoDigits).day(.twoDigits))) }.font(.system(size:10)).foregroundStyle(.secondary).offset(y:y+27)
            }
        }
    }
}
