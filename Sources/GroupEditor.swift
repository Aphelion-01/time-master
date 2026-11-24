import SwiftUI

struct GroupEditor:View {
    @ObservedObject var store=Store.shared
    @ObservedObject var groups=GroupStore.shared
    @State var group:EventGroup
    let isNew:Bool
    @State private var search=""
    @State private var hideOriginals=false
    @State private var dissolving=false
    var selected:[Event] { group.members(in:store.events) }
    var valid:Bool { !group.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && selected.count>=2 && groups.error==nil }
    var candidates:[Event] { store.events.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }.sorted {$0.end<$1.end} }
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            VStack(alignment:.leading,spacing:8) {
                Text(isNew ? "把日子放在一起" : "编辑组合").font(.system(size:24,weight:.semibold))
                Text("共享一张玻璃面板，每个事件保留自己的时间。").font(.system(size:11)).foregroundStyle(.secondary)
            }.padding(26)
            HStack(alignment:.top,spacing:26) {
                ScrollView {
                    VStack(alignment:.leading,spacing:20) {
                        SettingSection("组合名称") { TextField("例如：考试安排",text:$group.title).textFieldStyle(.roundedBorder) }
                        SettingSection("选择事件 · 已选 \(selected.count) 个") {
                            VStack(alignment:.leading,spacing:12) {
                                TextField("搜索事件",text:$search).textFieldStyle(.roundedBorder)
                                if store.events.isEmpty { Text("先在菜单栏添加至少两个倒计时。").font(.system(size:11)).foregroundStyle(.secondary) }
                                ForEach(candidates) { e in
                                    Toggle(isOn:Binding(get:{group.eventIDs.contains(e.id)},set:{ selected in if selected { if !group.eventIDs.contains(e.id) { group.eventIDs.append(e.id) } } else { group.eventIDs.removeAll {$0==e.id} } })) {
                                        HStack {
                                            VStack(alignment:.leading,spacing:4) { Text(e.title).font(.system(size:12)); Text(e.end.formatted(.dateTime.month().day())).font(.system(size:10)).foregroundStyle(.secondary) }
                                            Spacer()
                                            Text(e.end<=Date() ? "已到期" : "\(e.remaining) 天后").font(.system(size:11)).foregroundStyle(e.tint)
                                        }
                                    }.toggleStyle(.checkbox)
                                }
                                if !store.events.isEmpty && selected.count<2 { Text("至少选择两个事件。").font(.system(size:10)).foregroundStyle(.secondary) }
                            }
                        }
                        SettingSection("图形与顺序") {
                            VStack(alignment:.leading,spacing:14) {
                                Picker("视图",selection:$group.style) { ForEach(GroupViewStyle.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                                Picker("排列",selection:$group.sort) { ForEach(GroupSort.allCases) { Text($0.title).tag($0) } }
                                if group.sort == .manual {
                                    ForEach(group.members(in:store.events)) { e in
                                        HStack { Text(e.title).font(.system(size:11)).lineLimit(1); Spacer(); Button { move(e.id,by:-1) } label: { Image(systemName:"chevron.up") }.disabled(group.eventIDs.first==e.id).help("上移"); Button { move(e.id,by:1) } label: { Image(systemName:"chevron.down") }.disabled(group.eventIDs.last==e.id).help("下移") }.buttonStyle(.borderless)
                                    }
                                }
                                Toggle("显示组合窗口",isOn:$group.visible).toggleStyle(.switch).font(.system(size:12))
                                Toggle("同时隐藏成员的独立卡片",isOn:$hideOriginals).toggleStyle(.checkbox).font(.system(size:11))
                            }
                        }
                    }.padding(.bottom,12)
                }.frame(width:390)
                VStack(alignment:.leading,spacing:16) {
                    Text("组合预览").font(.system(size:12,weight:.medium)).foregroundStyle(.secondary)
                    GroupPreview(group:group,events:store.events).frame(height:330)
                    Text(group.style.detail).font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).lineSpacing(4)
                    Text("组合引用原事件，不创建副本。\n编辑成员会同步更新其他组合和独立卡片。").font(.system(size:10)).foregroundStyle(.tertiary).lineSpacing(5)
                }.frame(width:366)
            }.padding(.horizontal,26)
            Spacer(minLength:10)
            Divider()
            HStack {
                if !isNew { Button("解散组合…",role:.destructive) { dissolving=true }.buttonStyle(.borderless).foregroundStyle(.red) }
                if let error=groups.error { Text(error).font(.system(size:10)).foregroundStyle(.red).lineLimit(2) }
                Spacer()
                Button("取消") { Windows.shared.closeGroupEditor() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "创建组合" : "保存组合") {
                    group.title=group.title.trimmingCharacters(in:.whitespacesAndNewlines)
                    if !isNew,let live=groups.groups.first(where:{$0.id==group.id}) {
                        group.x=live.x; group.y=live.y; group.width=live.width; group.height=live.height
                    }
                    group.eventIDs=group.uniqueIDs.filter { id in store.events.contains {$0.id==id} }
                    if groups.upsert(group) {
                        if hideOriginals { for var e in selected { e.visible=false; store.upsert(e) } }
                        Windows.shared.closeGroupEditor()
                    }
                }.buttonStyle(.borderedProminent).disabled(!valid).keyboardShortcut(.defaultAction)
            }.padding(20)
        }.frame(width:860,height:680).background(Color(red:0.075,green:0.085,blue:0.11)).foregroundStyle(.white).preferredColorScheme(.dark).tint(.indigo)
            .alert("解散“\(group.title)”？",isPresented:$dissolving) {
                Button("取消",role:.cancel) {}
                Button("仅解散组合",role:.destructive) { dissolve(restore:false) }
                Button("解散并显示独立卡片") { dissolve(restore:true) }
            } message: { Text("不会删除任何事件。你可以选择是否恢复成员的独立卡片。") }
    }
    func move(_ id:UUID,by delta:Int) {
        guard let i=group.eventIDs.firstIndex(of:id),group.eventIDs.indices.contains(i+delta) else { return }
        group.eventIDs.swapAt(i,i+delta)
    }
    func dissolve(restore:Bool) { groups.remove(group.id,restoreMembers:restore); if groups.error==nil { Windows.shared.closeGroupEditor() } }
}
struct GroupPreview:View {
    var group:EventGroup
    var events:[Event]
    var body:some View {
        GeometryReader { proxy in
            let factor=min((proxy.size.width-24)/group.size.width,(proxy.size.height-24)/group.size.height)
            ZStack {
                LinearGradient(colors:[Color(red:0.17,green:0.20,blue:0.34),Color(red:0.12,green:0.24,blue:0.29),Color(red:0.21,green:0.17,blue:0.27)],startPoint:.topLeading,endPoint:.bottomTrailing)
                GroupSurface(group:group,events:events,size:group.size,preview:true)
                    .scaleEffect(factor).frame(width:group.size.width*factor,height:group.size.height*factor)
            }.frame(width:proxy.size.width,height:proxy.size.height).clipShape(.rect(cornerRadius:18))
        }
    }
}

struct GroupManagementView:View {
    @ObservedObject var groups=GroupStore.shared
    @ObservedObject var store=Store.shared
    @Binding var selectedID:UUID?
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Button { Windows.shared.editGroup() } label: { Label("新建组合",systemImage:"rectangle.stack.badge.plus") }.buttonStyle(.borderedProminent).disabled(store.events.count<2 || groups.error != nil)
            if let error=groups.error { Text(error).font(.caption).foregroundStyle(.red) }
            if groups.groups.isEmpty {
                Text("把考试、项目或纪念日放在同一张面板里。至少需要两个事件；原有事件会保留。").font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(5)
            }
            ForEach(groups.groups) { group in
                VStack(alignment:.leading,spacing:14) {
                    Button { selectedID=group.id } label: {
                        VStack(alignment:.leading,spacing:7) { Text(group.title).font(.system(size:14,weight:.medium)); Text("\(group.members(in:store.events).count) 个事件 · \(group.style.title)").font(.system(size:10)).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    HStack { Button("编辑组合") { Windows.shared.editGroup(group) }; Spacer(); Toggle("显示",isOn:Binding(get:{group.visible},set:{value in var g=group; g.visible=value; groups.upsert(g)})).toggleStyle(.switch).font(.system(size:11)).fixedSize() }.buttonStyle(.bordered)
                }.padding(16).background(.white.opacity(0.04),in:.rect(cornerRadius:13)).overlay { RoundedRectangle(cornerRadius:13).stroke(selectedID==group.id ? .indigo.opacity(0.6) : .white.opacity(0.04),lineWidth:1) }
            }
        }
    }
}
