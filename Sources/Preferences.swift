import SwiftUI
import AppKit

@MainActor final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard
    @Published var motion: Bool { didSet { defaults.set(motion,forKey:"motionEnabled") } }
    @Published var snapping: Bool { didSet { defaults.set(snapping,forKey:"snapEnabled") } }
    @Published var systemWidgets: Bool { didSet { defaults.set(systemWidgets,forKey:"widgetSnap") } }
    @Published var distance: Double { didSet { defaults.set(distance,forKey:"snapDistance") } }
    @Published var gap: Double { didSet { defaults.set(gap,forKey:"cardGap") } }
    @Published var depth: Double { didSet { defaults.set(depth,forKey:"glassDepth") } }
    @Published var layer:CardLayer { didSet { defaults.set(layer.rawValue,forKey:"cardLayer"); Windows.shared.applyLayers() } }
    init() {
        let d = UserDefaults.standard
        layer = CardLayer(rawValue:d.string(forKey:"cardLayer") ?? "normal") ?? .normal
        motion = d.object(forKey:"motionEnabled") as? Bool ?? true
        snapping = d.object(forKey:"snapEnabled") as? Bool ?? true
        systemWidgets = d.object(forKey:"widgetSnap") as? Bool ?? true
        distance = min(32,max(8,d.object(forKey:"snapDistance") as? Double ?? 16))
        gap = min(24,max(0,d.object(forKey:"cardGap") as? Double ?? 12))
        depth = min(0.35,max(0,d.object(forKey:"glassDepth") as? Double ?? 0))
    }
    var allowsMotion: Bool { motion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

@MainActor final class CardInteraction: ObservableObject {
    @Published var angle = 0.0
    @Published var sx = 1.0
    @Published var sy = 1.0
    @Published var dx = 0.0
    @Published var dy = 0.0
    @Published var active = false
    private var releaseTask: Task<Void,Never>?
    func begin() { releaseTask?.cancel(); active = true }
    func follow(vx: Double,vy: Double) {
        guard Preferences.shared.allowsMotion else { neutral(); return }
        let f = DragFeedback.resolve(vx:vx,vy:vy)
        withAnimation(.spring(duration:0.5,bounce:0.2)) {
            angle=f.angle; sx=f.stretchX; sy=f.stretchY; dx=f.lagX; dy=f.lagY
        }
    }
    func release(displacement: CGSize = .zero) {
        active = false
        releaseTask?.cancel()
        guard Preferences.shared.allowsMotion else { neutral(); return }
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { dx += displacement.width; dy += displacement.height }
        releaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for:.milliseconds(16))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration:0.5,bounce:0.2)) { self?.neutral() }
        }
    }
    func neutral() { angle=0; sx=1; sy=1; dx=0; dy=0 }
    deinit { releaseTask?.cancel() }
}
