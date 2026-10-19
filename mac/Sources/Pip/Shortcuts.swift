import AppKit
import Carbon

/// A modifier key used alone as a button. Only right-side keys and fn: the left ones are part of everyday shortcuts.
enum ModifierKey: String, Codable, CaseIterable {
	case rightOption, rightCommand, rightControl, rightShift, fn
	/// ⌘⌥⇧ pressed together, which is what a Caps Lock "Hyper key" (Raycast and similar) sends.
	case hyper

	/// The three modifiers that make up `hyper`.
	static let hyperFlags: NSEvent.ModifierFlags = [.command, .option, .shift]

	var keyCode: UInt16 {
		switch self {
		case .rightOption: 61
		case .rightCommand: 54
		case .rightControl: 62
		case .rightShift: 60
		case .fn: 63
		case .hyper: 0 // several keys; matched by flags instead
		}
	}

	/// Flag bits that are set while this exact key is down (device-dependent bits tell right from left).
	var mask: UInt {
		switch self {
		case .rightOption: 0x40
		case .rightCommand: 0x10
		case .rightControl: 0x2000
		case .rightShift: 0x04
		case .fn: NSEvent.ModifierFlags.function.rawValue
		case .hyper: ModifierKey.hyperFlags.rawValue
		}
	}

	var label: String {
		switch self {
		case .rightOption: "Right ⌥ (AltGr)"
		case .rightCommand: "Right ⌘"
		case .rightControl: "Right ⌃"
		case .rightShift: "Right ⇧"
		case .fn: "fn (Globe)"
		case .hyper: "Caps Lock (⌘⌥⇧)"
		}
	}

	static func from(keyCode: UInt16) -> ModifierKey? { allCases.first { $0 != .hyper && $0.keyCode == keyCode } }
}

/// What starts dictation: a key combination, a single modifier key, or nothing.
enum ShortcutSpec: Codable, Equatable {
	case combo(keyCode: UInt32, modifiers: UInt32, label: String)
	case modifier(ModifierKey)
	case none

	var label: String {
		switch self {
		case let .combo(_, _, label): label
		case let .modifier(key): key.label
		case .none: "None"
		}
	}

	static let dictateDefault = ShortcutSpec.combo(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), label: "⌃⌥Space")

	/// Load a shortcut from this app's isolated preference domain.
	static func load(_ key: String, default fallback: ShortcutSpec) -> ShortcutSpec {
		if let data = UserDefaults.standard.data(forKey: key), let spec = try? JSONDecoder().decode(ShortcutSpec.self, from: data) {
			return spec
		}

		return fallback
	}

	func save(_ key: String) {
		if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: key) }
	}

	// MARK: Building one from a key press

	private static let names: [UInt16: String] = [
		49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 117: "⌦", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
		123: "←", 124: "→", 125: "↓", 126: "↑",
		122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
		103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
	]
	private static let functionKeys: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]

	/// A combination from a key press, or nil when it would get in the way of typing
	/// (a plain key, or only ⇧): it needs ⌃, ⌥ or ⌘, unless it's a function key.
	static func combo(from event: NSEvent) -> ShortcutSpec? {
		let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
		let isFunctionKey = functionKeys.contains(event.keyCode)
		guard isFunctionKey || !flags.intersection([.control, .option, .command]).isEmpty else { return nil }
		var modifiers = 0
		var label = ""
		if flags.contains(.control) { modifiers |= controlKey; label += "⌃" }
		if flags.contains(.option) { modifiers |= optionKey; label += "⌥" }
		if flags.contains(.shift) { modifiers |= shiftKey; label += "⇧" }
		if flags.contains(.command) { modifiers |= cmdKey; label += "⌘" }
		let key = names[event.keyCode] ?? (event.charactersIgnoringModifiers ?? "?").uppercased()
		return .combo(keyCode: UInt32(event.keyCode), modifiers: UInt32(modifiers), label: label + key)
	}
}
