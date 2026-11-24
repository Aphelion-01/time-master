import AppKit

extension CardLayer {
    var windowLevel:NSWindow.Level {
        switch self {
        case .floating: return .floating
        case .normal: return .normal
        // Keep the card above Finder's desktop icons and below normal windows.
        case .desktop: return NSWindow.Level(rawValue:Int(CGWindowLevelForKey(.desktopIconWindow))+1)
        }
    }
    var windowBehavior:NSWindow.CollectionBehavior {
        switch self {
        case .floating: return [.canJoinAllSpaces,.fullScreenAuxiliary]
        case .normal: return [.managed,.participatesInCycle]
        case .desktop: return [.canJoinAllSpaces,.stationary,.ignoresCycle]
        }
    }
}
