import AppKit

/// The status light of the Rams system (8 px): hollow ink3 when idle or done, filled green (`go`) while working with a
/// fine `go` arc orbiting it (Design choices: a still dot didn't read as running; green = running, like a Braun
/// device's "on" light; reduced motion keeps the dot alone), orange with a 3 px halo when it needs attention. It follows
/// the appearance it's drawn in.
final class RamsLightView: NSView {
	enum Kind: Equatable { case idle, work, need }

	static let size: CGFloat = 16
	var kind: Kind = .work { didSet { needsDisplay = true; updateOrbit() } }
	private let orbit = CAShapeLayer()

	override init(frame: NSRect) {
		super.init(frame: frame)
		wantsLayer = true
		orbit.fillColor = nil
		orbit.lineWidth = 1.5
		orbit.lineCap = .round
		layer?.addSublayer(orbit)
	}

	required init?(coder: NSCoder) { fatalError() }

	override var intrinsicContentSize: NSSize { NSSize(width: Self.size, height: Self.size) }

	override func layout() {
		super.layout()
		updateOrbit()
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		updateOrbit()
	}

	override func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		updateOrbit()
	}

	/// A quarter arc 16 px across, turning once every 1.6 s, only while working, shown and motion allowed.
	private func updateOrbit() {
		let turning = kind == .work && window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
		orbit.isHidden = !turning
		guard turning else { orbit.removeAllAnimations(); return }
		let box = CGRect(x: (bounds.width - 16) / 2, y: (bounds.height - 16) / 2, width: 16, height: 16)
		orbit.frame = box
		let path = CGMutablePath()
		path.addArc(center: CGPoint(x: 8, y: 8), radius: 7.25, startAngle: .pi / 4, endAngle: .pi * 3 / 4, clockwise: false)
		orbit.path = path
		effectiveAppearance.performAsCurrentDrawingAppearance { self.orbit.strokeColor = Rams.go.cgColor }
		if orbit.animation(forKey: "orbit") == nil {
			let spin = CABasicAnimation(keyPath: "transform.rotation.z")
			spin.fromValue = 0
			spin.toValue = -2 * Double.pi
			spin.duration = 1.6
			spin.repeatCount = .infinity
			spin.isRemovedOnCompletion = false
			orbit.add(spin, forKey: "orbit")
		}
	}

	override func draw(_ dirtyRect: NSRect) {
		let dot = NSRect(x: (bounds.width - 8) / 2, y: (bounds.height - 8) / 2, width: 8, height: 8)
		switch kind {
		case .idle:
			Rams.ink3.setStroke()
			let ring = NSBezierPath(ovalIn: dot.insetBy(dx: 0.75, dy: 0.75))
			ring.lineWidth = 1.5
			ring.stroke()
		case .work:
			Rams.go.setFill()
			NSBezierPath(ovalIn: dot).fill()
		case .need:
			Rams.accBg.setFill()
			NSBezierPath(ovalIn: dot.insetBy(dx: -3, dy: -3)).fill()
			Rams.acc.setFill()
			NSBezierPath(ovalIn: dot).fill()
		}
	}

}

/// The voice meter while listening: five thin bars in ink2, the newest level on the right. Static between levels.
final class RamsLevelBars: NSView {
	private var levels = [Float](repeating: 0, count: 5)
	override var intrinsicContentSize: NSSize { NSSize(width: 5 * 2 + 4 * 2, height: 14) }

	func push(level: Float) {
		levels.removeFirst()
		levels.append(level.isFinite ? min(max(level, 0), 1) : 0)
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect) {
		Rams.ink2.setFill()
		for (i, level) in levels.enumerated() {
			let height = 3 + CGFloat(level) * (bounds.height - 3)
			NSBezierPath(roundedRect: NSRect(x: CGFloat(i) * 4, y: (bounds.height - height) / 2, width: 2, height: height), xRadius: 1, yRadius: 1).fill()
		}
	}
}

/// A floating surface of the Rams system (the pill, the cards by the pointer): raise, a 1 px line, the one shadow.
/// Its layer's colours are set again when the appearance changes.
class RamsSurfaceView: NSView {
	var radius: CGFloat = 12 { didSet { needsDisplay = true } }
	/// The edge: the line, or the accent for a question that needs attention.
	var edge: NSColor = Rams.line { didSet { needsDisplay = true } }

	override init(frame: NSRect) {
		super.init(frame: frame)
		wantsLayer = true
	}

	/// Inside a window, the view draws the shadow itself; in an overlay panel the panel casts it (hasShadow), since a
	/// view's shadow falls outside the panel and is cut off.
	func castShadow() {
		shadow = {
			let shadow = NSShadow()
			shadow.shadowColor = NSColor(white: 0, alpha: 0.16)
			shadow.shadowOffset = NSSize(width: 0, height: -4)
			shadow.shadowBlurRadius = 12
			return shadow
		}()
	}

	required init?(coder: NSCoder) { fatalError() }

	override var wantsUpdateLayer: Bool { true }
	override func updateLayer() {
		layer?.backgroundColor = Rams.raise.cgColor
		layer?.cornerRadius = radius
		layer?.borderWidth = 1
		layer?.borderColor = edge.cgColor
	}
}
