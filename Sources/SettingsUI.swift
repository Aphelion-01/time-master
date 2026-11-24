import SwiftUI
import AppKit

private let accent = Color(red:0.49,green:0.54,blue:1)
private let settingsBackground = Color(red:0.075,green:0.085,blue:0.11)

enum SettingsPane: String, CaseIterable, Identifiable {
    case appearance = "卡片外观", groups = "组合记录", interaction = "拖动与吸附", data = "数据与备份"
    var id:String { rawValue }
    var symbol:String { switch self { case .appearance:return "rectangle.on.rectangle"; case .groups:return "rectangle.stack"; case .interaction:return "cursorarrow.motionlines"; case .data:return "externaldrive" } }
    var subtitle:String { switch self { case .appearance:return "调整大小与图形，结果就在右侧。"; case .groups:return "相关的日子，在同一张面板里相遇。"; case .interaction:return "跟随你的手势，在合适的位置停下。"; case .data:return "重要的日子，始终保存在你的 Mac。" } }
}
private struct SearchEntry: Identifiable {
    let title:String, detail:String
    let pane:SettingsPane
    var id:String { title }
    static let all:[Self] = [
        .init(title:"组合记录",detail:"新建组合 成员 排序 共同时间轴 余量对照 并列卡片",pane:.groups),
        .init(title:"桌面图层",detail:"置顶 常驻 屏幕 普通窗口 固定桌面 层级",pane:.appearance),
        .init(title:"卡片大小",detail:"紧凑 标准 宽幅 展开 缩放 自动排版",pane:.appearance),
        .init(title:"图形样式",detail:"点阵 圆环 刻度 颜色 强调色",pane:.appearance),
        .init(title:"材质深度",detail:"深色 透明 玻璃 背景",pane:.appearance),
        .init(title:"弹性反馈",detail:"拖动 惯性 回弹 动画 动效",pane:.interaction),
        .init(title:"自动吸附",detail:"屏幕 边缘 小组件 卡片 Shift",pane:.interaction),
        .init(title:"吸附距离与间距",detail:"阈值 像素 距离 对齐",pane:.interaction),
        .init(title:"导入与导出",detail:"备份 恢复 JSON 数据",pane:.data)
    ]
}

struct SettingsView: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var groups=GroupStore.shared
    @ObservedObject var preferences = Preferences.shared
    @AppStorage("settingsPane") private var paneName=SettingsPane.appearance.rawValue
    @State var selectedID:UUID?
    @State private var selectedGroupID:UUID?
    @State private var query=""
    @FocusState private var searchFocused:Bool
    @StateObject private var demoMotion=CardInteraction()
    var pane:SettingsPane { SettingsPane(rawValue:paneName) ?? .appearance }
    var selected:Event? { store.events.first(where:{$0.id==selectedID}) ?? store.events.first }
    var preview:Event {
        selected ?? Event(title:"新的倒计时",start:Calendar.current.date(byAdding:.day,value:-23,to:.now)!,end:Calendar.current.date(byAdding:.day,value:19,to:.now)!)
    }
    private var results:[SearchEntry] { SearchEntry.all.filter { ($0.title+" "+$0.detail).localizedCaseInsensitiveContains(query) } }
    var body:some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:22) {
                HStack(spacing:9) { Image(systemName:"hourglass").foregroundStyle(accent); Text("Time Master").font(.system(size:14,weight:.semibold)) }.padding(.top,12)
                HStack(spacing:7) { Image(systemName:"magnifyingglass").foregroundStyle(.secondary); TextField("搜索设置",text:$query).textFieldStyle(.plain).focused($searchFocused) }
                    .font(.system(size:11)).padding(9).background(.white.opacity(0.06),in:.rect(cornerRadius:9))
                VStack(spacing:5) {
                    ForEach(SettingsPane.allCases) { p in
                        Button { paneName=p.rawValue; query=""; Windows.shared.settingsWindow?.title="\(p.rawValue) · Time Master" } label: {
                            Label(p.rawValue,systemImage:p.symbol).font(.system(size:12,weight:p==pane ? .semibold : .regular)).frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,11).padding(.horizontal,10)
                                .foregroundStyle(p==pane ? .white : .white.opacity(0.62)).background(p==pane ? .white.opacity(0.09) : .clear,in:.rect(cornerRadius:10))
                        }.buttonStyle(.plain)
                    }
                }
                Spacer()
                Text("Time Master 0.4\n所有更改即时保存").font(.system(size:10)).foregroundStyle(.tertiary).lineSpacing(5)
            }.padding(18).frame(width:178).background(.white.opacity(0.025))
            Divider().opacity(0.35)
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    VStack(alignment:.leading,spacing:9) { Text(query.isEmpty ? pane.rawValue : "搜索结果").font(.system(size:24,weight:.semibold)); Text(query.isEmpty ? pane.subtitle : "找到 \(results.count) 个相关设置").font(.system(size:11)).foregroundStyle(.secondary) }
                    if !query.isEmpty {
                        if results.isEmpty { ContentUnavailableView.search(text:query) }
                        ForEach(results) { entry in
                            Button { paneName=entry.pane.rawValue; query="" } label: {
                                HStack { VStack(alignment:.leading,spacing:6) { Text(entry.title).font(.system(size:13,weight:.medium)); Text(entry.pane.rawValue).font(.system(size:10)).foregroundStyle(.secondary) }; Spacer(); Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary) }.padding(14).background(.white.opacity(0.04),in:.rect(cornerRadius:12))
                            }.buttonStyle(.plain)
                        }
                    } else {
                        switch pane {
                        case .appearance: appearance
                        case .groups: GroupManagementView(selectedID:$selectedGroupID)
                        case .interaction: interaction
                        case .data: data
                        }
                    }
                }.padding(26).frame(maxWidth:.infinity,alignment:.leading)
            }.frame(width:410)
            Divider().opacity(0.35)
            previewPane.frame(maxWidth:.infinity,maxHeight:.infinity)
        }.frame(width:940,height:640).background(settingsBackground).foregroundStyle(.white).preferredColorScheme(.dark).tint(accent)
            .onExitCommand { Windows.shared.settingsWindow?.close() }
            .background { Button("") { searchFocused=true }.keyboardShortcut("f",modifiers:.command).hidden().accessibilityHidden(true) }
    }
    @ViewBuilder var appearance:some View {
        if !store.events.isEmpty {
            Picker("正在调整",selection:Binding(get:{selected?.id ?? UUID()},set:{selectedID=$0})) { ForEach(store.events) { Text($0.title).tag($0.id) } }.font(.system(size:12))
        }
        SettingSection("桌面图层") {
            VStack(alignment:.leading,spacing:12) {
                Picker("显示方式",selection:$preferences.layer) {
                    ForEach(CardLayer.allCases) { layer in Text(layer.title).tag(layer) }
                }.pickerStyle(.segmented)
                Text(preferences.layer.detail).font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                Text("应用到所有桌面卡片，更改立即生效。").font(.system(size:10)).foregroundStyle(.tertiary)
            }
        }
        SettingSection("大小与排版") {
            VStack(alignment:.leading,spacing:14) {
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10) {
                    ForEach(CardLayout.allCases) { layout in
                        Button { if let e=selected { Windows.shared.resizeCard(e.id,to:layout.size) } } label: {
                            VStack(alignment:.leading,spacing:7) {
                                HStack { Text(layout.rawValue).font(.system(size:12,weight:.medium)); Spacer(); if CardLayout.resolve(preview.cardSize)==layout { Image(systemName:"checkmark.circle.fill").foregroundStyle(accent) } }
                                Text("\(Int(layout.size.width)) × \(Int(layout.size.height))").font(.system(size:10)).foregroundStyle(.secondary)
                            }.padding(11).background(CardLayout.resolve(preview.cardSize)==layout ? accent.opacity(0.12) : .white.opacity(0.035),in:.rect(cornerRadius:10))
                                .overlay { RoundedRectangle(cornerRadius:10).stroke(CardLayout.resolve(preview.cardSize)==layout ? accent.opacity(0.5) : .white.opacity(0.07),lineWidth:1) }
                        }.buttonStyle(.plain).disabled(selected == nil)
                    }
                }
                Text("也可拖动卡片右下角。布局随大小自动切换，紧凑版优先显示日期与天数。").font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).lineSpacing(4)
            }
        }
        SettingSection("图形与颜色") {
            VStack(alignment:.leading,spacing:18) {
                Picker("图形",selection:Binding(get:{preview.style},set:{value in update { $0.style=value }})) { ForEach(DisplayStyle.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).disabled(selected == nil)
                HStack {
                    Text("强调色").font(.system(size:12)); Spacer()
                    ForEach(0..<5) { i in
                        Button { update { $0.color=i } } label: { Circle().fill([Color.indigo,.teal,.pink,.orange,.gray][i]).frame(width:23,height:23).overlay { if preview.color==i { Image(systemName:"checkmark").font(.system(size:10,weight:.bold)).foregroundStyle(.white) } } }.buttonStyle(.plain).disabled(selected == nil).accessibilityLabel("强调色 \(i+1)")
                    }
                }
            }
        }
        SettingSection("材质") {
            VStack(alignment:.leading,spacing:12) {
                HStack { Text("背景深度").font(.system(size:12)); Spacer(); Text("\(Int(preferences.depth/0.35*100))%").font(.system(size:10)).foregroundStyle(.secondary).monospacedDigit() }
                Slider(value:$preferences.depth,in:0...0.35)
                Text("保留深色透明玻璃，只调整背景的遮盖程度。").font(.system(size:10)).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder var interaction:some View {
        SettingSection("交互反馈") {
            VStack(alignment:.leading,spacing:14) {
                Toggle(isOn:$preferences.motion) { VStack(alignment:.leading,spacing:6) { Text("弹性拖动").font(.system(size:12)); Text("随速度轻微倾斜，松手后回弹。").font(.system(size:10)).foregroundStyle(.secondary) } }.toggleStyle(.switch)
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { Text("系统“减少动态效果”已开启，弹动会自动停用。").font(.system(size:10)).foregroundStyle(.secondary) }
                Button("试试回弹") {
                    demoMotion.begin(); demoMotion.follow(vx:1700,vy:300)
                    Task { @MainActor in try? await Task.sleep(for:.milliseconds(120)); demoMotion.release() }
                }.buttonStyle(.bordered).disabled(!preferences.allowsMotion)
            }
        }
        SettingSection("对齐与吸附") {
            VStack(alignment:.leading,spacing:18) {
                Toggle("自动吸附",isOn:$preferences.snapping).toggleStyle(.switch)
                Toggle("吸附系统小组件",isOn:$preferences.systemWidgets).toggleStyle(.switch).disabled(!preferences.snapping)
                VStack(alignment:.leading,spacing:8) {
                    HStack { Text("吸附范围"); Spacer(); Text("\(Int(preferences.distance)) pt").foregroundStyle(.secondary).monospacedDigit() }
                    Slider(value:$preferences.distance,in:8...32,step:2).disabled(!preferences.snapping)
                }
                VStack(alignment:.leading,spacing:8) {
                    HStack { Text("卡片间距"); Spacer(); Text("\(Int(preferences.gap)) pt").foregroundStyle(.secondary).monospacedDigit() }
                    Slider(value:$preferences.gap,in:0...24,step:2).disabled(!preferences.snapping)
                }
            }.font(.system(size:12))
        }
        Text("按住 Shift 松手可跳过吸附。系统小组件需暴露独立窗口边界；所有位置在松手后保存。").font(.system(size:10)).foregroundStyle(.secondary).lineSpacing(5)
    }
    @ViewBuilder var data:some View {
        SettingSection("本地数据") {
            VStack(alignment:.leading,spacing:14) {
                HStack { Text("倒计时事件"); Spacer(); Text("\(store.events.count) 个").foregroundStyle(.secondary) }.font(.system(size:12))
                Text("事件、组合、位置与大小保存在本机。导入会按标识合并，现有其他记录会保留。").font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).lineSpacing(4)
                HStack { Button("导出备份…") { Windows.shared.exportData() }; Button("导入备份…") { Windows.shared.importData() } }.buttonStyle(.bordered)
            }
        }
        SettingSection("使用方式") {
            VStack(alignment:.leading,spacing:13) {
                shortcut("双击卡片","编辑倒计时")
                shortcut("右键卡片","打开快捷菜单")
                shortcut("拖动右下角","调整大小")
                shortcut("⌘ ,","打开设置")
                shortcut("⌘ F","搜索设置")
            }
        }
        if let error=store.error { Text(error).font(.caption).foregroundStyle(.red) }
    }
    func shortcut(_ key:String,_ action:String) -> some View { HStack { Text(key).foregroundStyle(.secondary); Spacer(); Text(action) }.font(.system(size:11)) }
    var previewPane:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Text("实时预览").font(.system(size:12,weight:.medium)); Spacer(); Image(systemName:"sparkle").foregroundStyle(.secondary) }
            if pane == .groups {
                if let group=groups.groups.first(where:{$0.id==selectedGroupID}) ?? groups.groups.first {
                    GroupPreview(group:group,events:store.events).frame(height:320)
                    Text(group.title).font(.system(size:12,weight:.medium))
                    Text(group.style.detail).font(.system(size:10)).foregroundStyle(.secondary).lineSpacing(4)
                    Spacer()
                    Button("编辑这个组合…") { Windows.shared.editGroup(group) }.buttonStyle(.bordered)
                } else {
                    ContentUnavailableView("还没有组合",systemImage:"rectangle.stack",description:Text("新建组合后可在这里预览。"))
                    Spacer()
                }
            } else {
                PreviewStage(event:preview,motion:demoMotion).frame(height:320)
                HStack { Text(CardLayout.resolve(preview.cardSize).rawValue); Spacer(); Text("\(Int(preview.cardSize.width)) × \(Int(preview.cardSize.height))") }.font(.system(size:11)).foregroundStyle(.secondary).monospacedDigit()
                Text("拖动与缩放不影响倒计时。\n图形表示时间余量，不代表任务完成度。").font(.system(size:10)).foregroundStyle(.tertiary).lineSpacing(5)
                Spacer()
                if let e=selected { Button("编辑这个事件…") { Windows.shared.edit(e) }.buttonStyle(.bordered) }
            }
        }.padding(22)
    }
    func update(_ transform:(inout Event)->Void) { if var event=selected { transform(&event); store.upsert(event) } }
}

struct SettingSection<Content:View>:View {
    let title:String
    let content:() -> Content
    init(_ title:String,@ViewBuilder content:@escaping () -> Content) { self.title=title; self.content=content }
    var body:some View { VStack(alignment:.leading,spacing:12) { Text(title).font(.system(size:12,weight:.medium)).foregroundStyle(.secondary); content().padding(15).frame(maxWidth:.infinity,alignment:.leading).background(.white.opacity(0.035),in:.rect(cornerRadius:13)).overlay { RoundedRectangle(cornerRadius:13).stroke(.white.opacity(0.045),lineWidth:1) } } }
}
struct PreviewStage:View {
    var event:Event
    @ObservedObject var motion:CardInteraction
    @ObservedObject var preferences=Preferences.shared
    var body:some View {
        GeometryReader { g in
            let factor=min((g.size.width-28)/event.cardSize.width,(g.size.height-28)/event.cardSize.height)
            ZStack {
                LinearGradient(colors:[Color(red:0.17,green:0.20,blue:0.34),Color(red:0.12,green:0.24,blue:0.29),Color(red:0.21,green:0.17,blue:0.27)],startPoint:.topLeading,endPoint:.bottomTrailing)
                CardSurface(event:event,size:event.cardSize,preview:true)
                    .scaleEffect(x:preferences.allowsMotion ? motion.sx : 1,y:preferences.allowsMotion ? motion.sy : 1)
                    .rotationEffect(.degrees(preferences.allowsMotion ? motion.angle : 0))
                    .offset(x:motion.dx,y:motion.dy)
                    .scaleEffect(factor)
                    .frame(width:event.cardSize.width*factor,height:event.cardSize.height*factor)
            }.frame(width:g.size.width,height:g.size.height).clipShape(.rect(cornerRadius:18))
        }.accessibilityLabel("倒计时卡片实时预览")
    }
}

struct Editor:View {
    @ObservedObject var store=Store.shared
    @State var event:Event
    let isNew:Bool
    @State private var deleting=false
    @StateObject private var motion=CardInteraction()
    var valid:Bool { !event.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && event.end>event.start && store.error==nil }
    var displayEvent:Event { var e=event; if e.title.isEmpty { e.title="未命名倒计时" }; return e }
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack { VStack(alignment:.leading,spacing:7) { Text(isNew ? "新的时间节点" : "编辑倒计时").font(.system(size:23,weight:.semibold)); Text("让重要的日子，在桌面有个位置。").font(.system(size:11)).foregroundStyle(.secondary) }; Spacer() }.padding(26)
            HStack(alignment:.top,spacing:26) {
                ScrollView {
                    VStack(alignment:.leading,spacing:22) {
                        SettingSection("时间节点") {
                            VStack(alignment:.leading,spacing:16) {
                                TextField("例如：英语六级",text:$event.title).textFieldStyle(.roundedBorder).font(.system(size:14))
                                DatePicker("起算",selection:$event.start,displayedComponents:[.date,.hourAndMinute])
                                DatePicker("截止",selection:$event.end,displayedComponents:[.date,.hourAndMinute])
                                if event.end<=event.start { Text("截止时间须晚于起算时间").font(.system(size:10)).foregroundStyle(.red) }
                            }
                        }
                        SettingSection("桌面卡片") {
                            VStack(alignment:.leading,spacing:16) {
                                Picker("图形",selection:$event.style) { ForEach(DisplayStyle.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                                HStack { Text("强调色").font(.system(size:12)); Spacer(); ForEach(0..<5) { i in Button { event.color=i } label: { Circle().fill([Color.indigo,.teal,.pink,.orange,.gray][i]).frame(width:23,height:23).overlay { if event.color==i { Image(systemName:"checkmark").font(.system(size:10,weight:.bold)).foregroundStyle(.white) } } }.buttonStyle(.plain).accessibilityLabel("颜色 \(i+1)") } }
                                Toggle("显示在桌面",isOn:$event.visible).toggleStyle(.switch).font(.system(size:12))
                            }
                        }
                    }.padding(.bottom,10)
                }.frame(width:365)
                VStack(alignment:.leading,spacing:16) {
                    Text("实时预览").font(.system(size:12,weight:.medium)).foregroundStyle(.secondary)
                    PreviewStage(event:displayEvent,motion:motion).frame(height:280)
                    HStack { Text(CardLayout.resolve(event.cardSize).rawValue); Spacer(); Text("\(Int(event.cardSize.width)) × \(Int(event.cardSize.height))") }.font(.system(size:10)).foregroundStyle(.secondary)
                    HStack(spacing:7) { ForEach(CardLayout.allCases) { layout in Button(layout.rawValue) { event.cardWidth=layout.size.width; event.cardHeight=layout.size.height }.buttonStyle(.bordered).tint(CardLayout.resolve(event.cardSize)==layout ? accent : nil) } }
                    Text("保存后应用到桌面；取消不会修改原事件。").font(.system(size:10)).foregroundStyle(.tertiary)
                }.frame(width:325)
            }.padding(.horizontal,26)
            Spacer(minLength:8)
            Divider()
            HStack {
                if !isNew { Button("删除事件",role:.destructive) { deleting=true }.buttonStyle(.borderless).foregroundStyle(.red) }
                if let error=store.error { Text(error).font(.system(size:10)).foregroundStyle(.red).lineLimit(2) }
                Spacer()
                Button("取消") { Windows.shared.closeEditor() }.keyboardShortcut(.cancelAction).buttonStyle(.bordered)
                Button(isNew ? "创建倒计时" : "保存更改") {
                    event.title=event.title.trimmingCharacters(in:.whitespacesAndNewlines); store.upsert(event)
                    if store.error==nil { Windows.shared.closeEditor() }
                }.buttonStyle(.borderedProminent).disabled(!valid).keyboardShortcut(.defaultAction)
            }.padding(20)
        }.frame(width:768,height:620).background(settingsBackground).foregroundStyle(.white).preferredColorScheme(.dark).tint(accent)
            .alert("删除“\(event.title)”？",isPresented:$deleting) {
                Button("取消",role:.cancel) {}
                Button("删除",role:.destructive) { store.remove(event.id); Windows.shared.closeEditor() }
            } message: { Text("可先在设置中导出备份。") }
    }
}
