import AppKit
import CoreGraphics
import Carbon.HIToolbox  // cmdKey / shiftKey / optionKey / controlKey

/// 사용자가 직접 녹화한 키보드 단축키.
/// 재발사에 필요한 keyCode/flags 외에 표시용 displayKey 문자도 함께 저장한다.
struct KeyShortcut: Codable, Hashable {
    let keyCode: UInt16
    /// CGEventFlags.rawValue. CGEventFlags는 OptionSet이라 직접 Codable이 아니므로 raw로 보관.
    let cgFlagsRaw: UInt64
    /// UI 표시용 키 이름 (예: "A", "Tab", "F12"). 녹화 시점에 결정해 영속화.
    let displayKey: String

    init(keyCode: UInt16, cgFlags: CGEventFlags, displayKey: String) {
        self.keyCode = keyCode
        self.cgFlagsRaw = cgFlags.rawValue
        self.displayKey = displayKey
    }

    var cgFlags: CGEventFlags { CGEventFlags(rawValue: cgFlagsRaw) }

    /// "⇧⌘A" 형태의 사용자 표시 문자열.
    var displayString: String {
        cgFlags.modifierSymbols + displayKey
    }

    /// NSEvent.keyDown으로부터 KeyShortcut을 만든다. modifier-only 입력은 nil.
    static func from(event: NSEvent) -> KeyShortcut? {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cgFlags = Self.toCGFlags(mods)
        let keyCode = event.keyCode

        if let name = Self.specialKeyName(for: keyCode) {
            return KeyShortcut(keyCode: keyCode, cgFlags: cgFlags, displayKey: name)
        }

        // modifier 떼고 본 글자(예: ⇧+a → "A")가 있으면 사용. 없거나 비표시 가능 문자만 있으면 무효.
        let chars = (event.charactersIgnoringModifiers ?? "").uppercased()
        let trimmed = chars.unicodeScalars.first.flatMap { scalar -> String? in
            scalar.value >= 0x20 ? String(scalar) : nil
        }
        guard let displayKey = trimmed, !displayKey.isEmpty else { return nil }
        return KeyShortcut(keyCode: keyCode, cgFlags: cgFlags, displayKey: displayKey)
    }

    private static func toCGFlags(_ mods: NSEvent.ModifierFlags) -> CGEventFlags {
        var f: CGEventFlags = []
        if mods.contains(.command) { f.insert(.maskCommand) }
        if mods.contains(.shift)   { f.insert(.maskShift) }
        if mods.contains(.option)  { f.insert(.maskAlternate) }
        if mods.contains(.control) { f.insert(.maskControl) }
        return f
    }

    /// 표시 가능한 특수 키 이름. 매핑에 없는 keyCode는 charactersIgnoringModifiers로 fallback.
    private static func specialKeyName(for keyCode: UInt16) -> String? {
        switch keyCode {
        case 0x24: return "Return"
        case 0x4C: return "Enter"
        case 0x30: return "Tab"
        case 0x31: return "Space"
        case 0x33: return "Delete"
        case 0x35: return "Esc"
        case 0x75: return "Fwd Del"
        case 0x73: return "Home"
        case 0x77: return "End"
        case 0x74: return "Page Up"
        case 0x79: return "Page Down"
        case 0x7B: return "←"
        case 0x7C: return "→"
        case 0x7D: return "↓"
        case 0x7E: return "↑"
        case 0x7A: return "F1"
        case 0x78: return "F2"
        case 0x63: return "F3"
        case 0x76: return "F4"
        case 0x60: return "F5"
        case 0x61: return "F6"
        case 0x62: return "F7"
        case 0x64: return "F8"
        case 0x65: return "F9"
        case 0x6D: return "F10"
        case 0x67: return "F11"
        case 0x6F: return "F12"
        default: return nil
        }
    }
}

extension CGEventFlags {
    /// "⌃⌥⇧⌘" 순서의 macOS 표준 modifier 심볼.
    /// 비어 있으면 빈 문자열.
    var modifierSymbols: String {
        var s = ""
        if contains(.maskControl)   { s += "⌃" }
        if contains(.maskAlternate) { s += "⌥" }
        if contains(.maskShift)     { s += "⇧" }
        if contains(.maskCommand)   { s += "⌘" }
        return s
    }

    /// Carbon `RegisterEventHotKey`가 요구하는 modifier 비트마스크.
    /// CGEventFlags(macOS native)와 Carbon 상수는 별개라 변환이 필요하다.
    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if contains(.maskCommand)   { m |= UInt32(cmdKey) }
        if contains(.maskShift)     { m |= UInt32(shiftKey) }
        if contains(.maskAlternate) { m |= UInt32(optionKey) }
        if contains(.maskControl)   { m |= UInt32(controlKey) }
        return m
    }
}

extension KeyShortcut {
    /// Carbon hotkey 등록용 modifier 비트마스크.
    var carbonModifiers: UInt32 { cgFlags.carbonModifiers }

    /// 글로벌 hotkey로 사용 가능한지 — modifier가 하나라도 있어야 한다.
    /// modifier 없는 단일 키를 글로벌 등록하면 시스템 전역에서 해당 키가 가로채져
    /// 사용자가 자기 발등을 찍는다(예: 'a' 키 입력 불가).
    var hasModifier: Bool { carbonModifiers != 0 }

    /// NSMenuItem.keyEquivalent에 안전하게 넣을 수 있는 1글자(소문자 ASCII) 또는 빈 문자열.
    /// macOS 메뉴는 lowercase 단일 ASCII가 표준이며, 그 외 키는 modifier만 표시한다.
    var menuKeyEquivalent: String {
        guard displayKey.count == 1,
              let scalar = displayKey.unicodeScalars.first,
              scalar.isASCII else { return "" }
        return displayKey.lowercased()
    }
}

extension CGEventFlags {
    /// CGEventFlags → NSEvent.ModifierFlags(메뉴 표시용).
    var nsEventModifierFlags: NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        if contains(.maskCommand)   { mask.insert(.command) }
        if contains(.maskShift)     { mask.insert(.shift) }
        if contains(.maskAlternate) { mask.insert(.option) }
        if contains(.maskControl)   { mask.insert(.control) }
        return mask
    }
}
