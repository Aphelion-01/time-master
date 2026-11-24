import Foundation
import CoreGraphics

enum CardLayout: String, CaseIterable, Identifiable {
    case compact = "紧凑", standard = "标准", wide = "宽幅", expanded = "展开"
    var id: String { rawValue }
    var size: CGSize {
        switch self {
        case .compact: return CGSize(width: 320,height: 160)
        case .standard: return CGSize(width: 430,height: 334)
        case .wide: return CGSize(width: 640,height: 240)
        case .expanded: return CGSize(width: 640,height: 450)
        }
    }
    static func resolve(_ size: CGSize) -> Self {
        if size.width < 360 || size.height < 210 { return .compact }
        if size.width >= 560 && size.height < 340 { return .wide }
        if size.width >= 560 || size.height >= 410 { return .expanded }
        return .standard
    }
}
struct CardGeometry {
    static let minimum = CGSize(width: 280,height: 140)
    static let maximum = CGSize(width: 760,height: 540)
    static func clamp(_ size: CGSize) -> CGSize {
        guard size.width.isFinite, size.height.isFinite else { return CardLayout.standard.size }
        return CGSize(width: min(maximum.width,max(minimum.width,size.width)),height: min(maximum.height,max(minimum.height,size.height)))
    }
    static func resize(_ frame: CGRect, translation: CGSize) -> CGRect {
        let size = clamp(CGSize(width: frame.width-28+translation.width,height: frame.height-28-translation.height))
        return CGRect(x: frame.minX,y:frame.maxY-size.height-28,width:size.width+28,height:size.height+28)
    }
}
extension Event {
    var cardSize: CGSize { CardGeometry.clamp(CGSize(width: cardWidth ?? 430,height: cardHeight ?? 334)) }
}
struct DragFeedback {
    let angle: Double
    let stretchX: Double
    let stretchY: Double
    let lagX: Double
    let lagY: Double
    static func resolve(vx: Double,vy: Double) -> Self {
        let x = vx.isFinite ? vx : 0, y = vy.isFinite ? vy : 0
        return Self(angle:min(1.8,max(-1.8,-x/700)),
                    stretchX:1+min(abs(x)/80000,0.012)-min(abs(y)/160000,0.006),
                    stretchY:1+min(abs(y)/80000,0.012)-min(abs(x)/160000,0.006),
                    lagX:min(5,max(-5,-x*0.002)),lagY:min(5,max(-5,y*0.002)))
    }
}


enum CardLayer: String, CaseIterable, Identifiable {
    case floating, normal, desktop
    var id:String { rawValue }
    var title:String {
        switch self { case .floating:return "始终置顶"; case .normal:return "普通窗口"; case .desktop:return "固定桌面" }
    }
    var detail:String {
        switch self {
        case .floating:return "显示在普通窗口上方，切换应用时仍可见。"
        case .normal:return "与普通窗口一起前后切换，不遮挡正在使用的应用。"
        case .desktop:return "放在桌面层，应用窗口会覆盖卡片；仍可拖动和缩放。"
        }
    }
}
