import AppKit
import ObjectiveC

private final class ButtonClosureTarget: NSObject {
	let action: () -> Void
	init(_ action: @escaping () -> Void) { self.action = action }
	@objc func fire() { action() }
}

extension NSButton {
	private static var actionAssociation: UInt8 = 0
	/// NSControl's target is weak; retain the closure on its button, not in a process-wide registry.
	func onClick(_ action: @escaping () -> Void) {
		let target = ButtonClosureTarget(action)
		objc_setAssociatedObject(self, &Self.actionAssociation, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
		self.target = target
		self.action = #selector(ButtonClosureTarget.fire)
	}
}
