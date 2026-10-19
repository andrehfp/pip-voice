import AppKit

/// Native warm-neutral colors. Accent marks a required action; green marks a running light.
enum Rams {
	/// Window, screen.
	static let bg = dynamic(light: 0xF2EEE6, dark: 0x1A1815)
	/// Field, card, menu, and the pill by the pointer.
	static let raise = dynamic(light: 0xFBF8F2, dark: 0x25211C)
	/// A key, and its 1 px edge.
	static let key = dynamic(light: 0xE8E2D6, dark: 0x2E2923)
	static let keyEdge = dynamic(light: 0xD2C9B9, dark: 0x433B31)
	static let line = dynamic(light: 0xDDD5C7, dark: 0x3A342C)
	/// The second surface tone (the sidebar, the work block). No shadow.
	static let panel = dynamic(light: 0xE9E3D7, dark: 0x231F1A)
	/// Text, the primary key.
	static let ink = dynamic(light: 0x1E1C19, dark: 0xF0EADF)
	/// Secondary text.
	static let ink2 = dynamic(light: 0x57524A, dark: 0xBDB4A6)
	/// Labels, times and the idle light.
	static let ink3 = dynamic(light: 0x776F63, dark: 0x9C9385)
	/// Text on an ink key.
	static let onInk = dynamic(light: 0xFBF8F2, dark: 0x1A1815)
	/// The one accent: only what needs attention.
	static let acc = dynamic(light: 0xE8590C, dark: 0xFF7A2B)
	static let accInk = dynamic(light: 0xB4460A, dark: 0xFF8A4C)
	static let accBg = NSColor(name: nil) { appearance in
		isDark(appearance) ? NSColor(hex: 0xFF7A2B).withAlphaComponent(0.12) : NSColor(hex: 0xE8590C).withAlphaComponent(0.10)
	}
	/// Running: only the working light's dot and orbit, never text or a fill.
	static let go = dynamic(light: 0x2E8540, dark: 0x5DC271)

	static func isDark(_ appearance: NSAppearance) -> Bool {
		appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight]).map { $0 == .darkAqua || $0 == .vibrantDark } ?? false
	}

	/// A colour resolved for `appearance` (a layer's CGColor doesn't follow the appearance by itself).
	static func cg(_ color: NSColor, for appearance: NSAppearance = NSApp.effectiveAppearance) -> CGColor {
		var resolved = color.cgColor
		appearance.performAsCurrentDrawingAppearance { resolved = color.cgColor }
		return resolved
	}

	private static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
		NSColor(name: nil) { appearance in NSColor(hex: isDark(appearance) ? dark : light) }
	}
}

/// A plain view filled with a Rams colour that follows the appearance (its layer is redrawn when the appearance changes).
final class RamsFillView: NSView {
	var color: NSColor = Rams.bg { didSet { needsDisplay = true } }
	override var wantsUpdateLayer: Bool { true }
	override func updateLayer() { layer?.backgroundColor = color.cgColor }
}
