import Foundation
import CoreGraphics

enum GroupViewStyle:String,Codable,CaseIterable,Identifiable {
    case lanes, timeline, tiles
    var id:String { rawValue }
    var title:String { switch self { case .lanes:return "余量对照"; case .timeline:return "共同时间轴"; case .tiles:return "并列卡片" } }
    var detail:String {
        switch self {
        case .lanes:return "各事件按自己的起算日期计算剩余比例。"
        case .timeline:return "所有截止日使用同一条时间尺度。"
        case .tiles:return "并排浏览事件，窗口变宽时自动增加列数。"
        }
    }
}
enum GroupSort:String,Codable,CaseIterable,Identifiable {
    case deadline, manual
    var id:String { rawValue }
    var title:String { self == .deadline ? "按截止日期" : "自定顺序" }
}
struct EventGroup:Codable,Identifiable,Equatable {
    var id=UUID()
    var title:String
    var eventIDs:[UUID]
    var style:GroupViewStyle = .lanes
    var sort:GroupSort = .deadline
    var visible=true
    var x:Double?=nil
    var y:Double?=nil
    var width:Double=560
    var height:Double=420
    var size:CGSize { GroupGeometry.clamp(CGSize(width:width,height:height)) }
    var uniqueIDs:[UUID] { var seen=Set<UUID>(); return eventIDs.filter { seen.insert($0).inserted } }
    func members(in events:[Event],now:Date = .now) -> [Event] {
        let lookup=events.reduce(into:[UUID:Event]()) { $0[$1.id]=$1 }
        let ordered=uniqueIDs.compactMap { lookup[$0] }
        guard sort == .deadline else { return ordered }
        let ranks=Dictionary(uniqueKeysWithValues:uniqueIDs.enumerated().map { ($0.element,$0.offset) })
        return ordered.sorted {
            let a=$0.end > now, b=$1.end > now
            if a != b { return a }
            if $0.end != $1.end { return a ? $0.end < $1.end : $0.end > $1.end }
            return ranks[$0.id,default:0] < ranks[$1.id,default:0]
        }
    }
}
struct GroupGeometry {
    static let minimum=CGSize(width:380,height:260)
    static let maximum=CGSize(width:960,height:720)
    static func clamp(_ size:CGSize) -> CGSize {
        guard size.width.isFinite,size.height.isFinite else { return CGSize(width:560,height:420) }
        return CGSize(width:min(maximum.width,max(minimum.width,size.width)),height:min(maximum.height,max(minimum.height,size.height)))
    }
    static func resize(_ frame:CGRect,translation:CGSize) -> CGRect {
        let s=clamp(CGSize(width:frame.width-28+translation.width,height:frame.height-28-translation.height))
        return CGRect(x:frame.minX,y:frame.maxY-s.height-28,width:s.width+28,height:s.height+28)
    }
    static func columns(width:CGFloat) -> Int { width>=800 ? 3 : (width>=560 ? 2 : 1) }
}
struct SharedTimeAxis {
    let now:Date
    let end:Date
    init(events:[Event],now:Date) {
        self.now=now
        end=events.map(\.end).filter { $0>now }.max() ?? now.addingTimeInterval(86400)
    }
    func fraction(for date:Date) -> Double { min(1,max(0,date.timeIntervalSince(now)/end.timeIntervalSince(now))) }
}
struct BackupDocument:Codable {
    var version=1
    var events:[Event]
    var groups:[EventGroup]
    static func read(_ data:Data) throws -> Self {
        let decoder=JSONDecoder()
        let document:Self
        if let old=try? decoder.decode([Event].self,from:data) { document=Self(events:old,groups:[]) }
        else { document=try decoder.decode(Self.self,from:data) }
        guard document.version==1,
              Set(document.events.map(\.id)).count==document.events.count,
              Set(document.groups.map(\.id)).count==document.groups.count,
              document.events.allSatisfy({$0.end>$0.start && !$0.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}),
              document.groups.allSatisfy({ !$0.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && $0.eventIDs.count==$0.uniqueIDs.count && Set($0.eventIDs).isSubset(of:Set(document.events.map(\.id))) }) else { throw CocoaError(.fileReadCorruptFile) }
        return document
    }
}
