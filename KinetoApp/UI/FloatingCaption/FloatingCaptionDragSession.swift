@MainActor
enum FloatingCaptionDragSource: Equatable {
    case captionHeader
    case companion
}

@MainActor
final class FloatingCaptionDragSession {
    private(set) var source: FloatingCaptionDragSource?

    var isActive: Bool { source != nil }
    var shouldSuppressCaption: Bool { source == .companion }

    func begin(_ source: FloatingCaptionDragSource) {
        guard self.source == nil || self.source == source else { return }
        self.source = source
    }

    func end() {
        source = nil
    }

    func reset() {
        source = nil
    }
}
