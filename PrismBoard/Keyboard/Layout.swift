import Foundation

enum KeyCap: Equatable {
    case char(String)
    case shift
    case backspace
    case plane(KeyPlane)
    case globe
    case space
    case ret
    case gif

    var display: String {
        switch self {
        case .char(let s): return s
        case .shift: return "⇧"
        case .backspace: return "⌫"
        case .plane(.letters): return "ABC"
        case .plane(.numbers): return "123"
        case .plane(.symbols): return "#+="
        case .globe: return "🌐"
        case .space: return "space"
        case .ret: return "return"
        case .gif: return "GIF"
        }
    }
}

enum KeyPlane {
    case letters, numbers, symbols
}

struct KeyRow { let keys: [KeyCap]; let weightedSides: Bool }

enum Layout {
    static let numberRow: [String] = ["1","2","3","4","5","6","7","8","9","0"]

    static func rows(for plane: KeyPlane, showNumberRow: Bool) -> [[KeyCap]] {
        switch plane {
        case .letters:
            var rows: [[KeyCap]] = []
            if showNumberRow { rows.append(numberRow.map { KeyCap.char($0) }) }
            rows.append("qwertyuiop".map { KeyCap.char(String($0)) })
            rows.append("asdfghjkl".map { KeyCap.char(String($0)) })
            rows.append([.shift] + "zxcvbnm".map { KeyCap.char(String($0)) } + [.backspace])
            rows.append(bottomRow(plane))
            return rows
        case .numbers:
            return [
                "1234567890".map { KeyCap.char(String($0)) },
                "-/:;()$&@\"".map { KeyCap.char(String($0)) },
                [.plane(.symbols)] + ".,?!'".map { KeyCap.char(String($0)) } + [.backspace],
                bottomRow(plane)
            ]
        case .symbols:
            return [
                "[]{}#%^*+=".map { KeyCap.char(String($0)) },
                "_\\|~<>€£¥•".map { KeyCap.char(String($0)) },
                [.plane(.numbers)] + ".,?!'".map { KeyCap.char(String($0)) } + [.backspace],
                bottomRow(plane)
            ]
        }
    }

    private static func bottomRow(_ plane: KeyPlane) -> [KeyCap] {
        let leftPlane: KeyCap = plane == .letters ? .plane(.numbers) : .plane(.letters)
        return [leftPlane, .globe, .gif, .space, .ret]
    }
}
