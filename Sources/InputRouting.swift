import CoreGraphics

struct MouseSound: Equatable {
    let key: String
    let down: Bool
}

// Only button identity and press/release state are used; never pointer position.
func mouseSound(for type: CGEventType, button: Int64) -> MouseSound? {
    switch type {
    case .leftMouseDown: return MouseSound(key: "KeyA", down: true)
    case .leftMouseUp: return MouseSound(key: "KeyA", down: false)
    case .rightMouseDown: return MouseSound(key: "KeyS", down: true)
    case .rightMouseUp: return MouseSound(key: "KeyS", down: false)
    case .otherMouseDown where button == 2: return MouseSound(key: "Space", down: true)
    case .otherMouseUp where button == 2: return MouseSound(key: "Space", down: false)
    default: return nil
    }
}

func inputEventMask(mouseEnabled: Bool) -> CGEventMask {
    var types: [CGEventType] = [.keyDown, .keyUp]
    if mouseEnabled {
        types += [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                  .otherMouseDown, .otherMouseUp]
    }
    return types.reduce(0) { $0 | (CGEventMask(1) << $1.rawValue) }
}
