import Foundation

enum GestureDirection: Int, CaseIterable, Codable {
    case left = 0, right, up, down

    var arrow: String {
        switch self {
        case .left:  return "←"
        case .right: return "→"
        case .up:    return "↑"
        case .down:  return "↓"
        }
    }

    var name: String {
        switch self {
        case .left:  return "Left"
        case .right: return "Right"
        case .up:    return "Up"
        case .down:  return "Down"
        }
    }
}

