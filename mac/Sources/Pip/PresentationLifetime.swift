import Foundation
import CoreGraphics

/// Cancellation cannot retract an animation completion already queued by AppKit.
struct PresentationLifetime {
	private(set) var generation: UInt64 = 0
	private(set) var shown = false
	@discardableResult mutating func show() -> UInt64 {
		generation &+= 1; shown = true; return generation
	}
	@discardableResult mutating func hide() -> UInt64 {
		generation &+= 1; shown = false; return generation
	}
	func isCurrent(_ generation: UInt64) -> Bool { self.generation == generation }
}

/// Positioning and glyph animation have independent clocks. A fixed caret needs neither pointer polling nor writes.
struct OverlayPlacementState {
	private var pointer: CGPoint?
	private var caret: CGRect?
	private var size: CGSize?
	private var ring = false
	mutating func reset() { self = Self() }
	mutating func needsPlacement(pointer: CGPoint, caret: CGRect?, size: CGSize, ring: Bool) -> Bool {
		let followsPointer = caret == nil || ring
		let changed = self.size != size || self.caret != caret || self.ring != ring || (followsPointer && self.pointer != pointer)
		self.pointer = pointer; self.caret = caret; self.size = size; self.ring = ring
		return changed
	}
	static func pollsPointer(caret: Bool, ring: Bool) -> Bool { !caret || ring }
}
