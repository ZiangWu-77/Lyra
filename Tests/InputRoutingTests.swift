import CoreGraphics

@main struct InputRoutingTests {
    static func main() {
        let pairs: [(CGEventType, CGEventType, Int64, String)] = [
            (.leftMouseDown, .leftMouseUp, 0, "KeyA"),
            (.rightMouseDown, .rightMouseUp, 1, "KeyS"),
            (.otherMouseDown, .otherMouseUp, 2, "Space")]
        for (down, up, button, key) in pairs {
            precondition(mouseSound(for: down, button: button) == MouseSound(key: key, down: true))
            precondition(mouseSound(for: up, button: button) == MouseSound(key: key, down: false))
            for type in [down, up] {
                let bit = CGEventMask(1) << type.rawValue
                precondition(inputEventMask(mouseEnabled: true) & bit != 0)
                precondition(inputEventMask(mouseEnabled: false) & bit == 0)
            }
        }
        for type: CGEventType in [.mouseMoved, .leftMouseDragged, .scrollWheel, .keyDown, .keyUp] {
            precondition(mouseSound(for: type, button: 0) == nil)
        }
        for type: CGEventType in [.mouseMoved, .scrollWheel, .leftMouseDragged] {
            precondition(inputEventMask(mouseEnabled: true) & (CGEventMask(1) << type.rawValue) == 0)
        }
        precondition(mouseSound(for: .otherMouseDown, button: 3) == nil)
        precondition(mouseSound(for: .otherMouseUp, button: 4) == nil)
        for enabled in [false, true] {
            for type: CGEventType in [.keyDown, .keyUp] {
                precondition(inputEventMask(mouseEnabled: enabled) & (CGEventMask(1) << type.rawValue) != 0)
            }
        }
        print("PASS: left/right/middle routing, releases, disabled mouse mask, ignored motion/scroll/side buttons")
    }
}
