import AppKit

/// A single modifier key used as a button, such as the right Option key (AltGr on ISO and ABNT keyboards).
/// Carbon hot keys can't watch a modifier alone, so this listens to keyboard events, which needs Accessibility.
@MainActor
final class ModifierTrigger {
	var key: ModifierKey? {
		didSet { isDown = false }
	}
	/// The key went down / came up.
	var onPress: () -> Void = {}
	var onRelease: () -> Void = {}
	/// Another key was pressed while it was held: the person is typing a symbol, not dictating.
	var onChord: () -> Void = {}
	var onEscape: () -> Void = {}

	private(set) var isDown = false
	private var monitors: [Any] = []

	/// Listen to keys in other apps (global) and in Pip's own windows (local).
	func start() {
		stop()
		let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
		if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
			MainActor.assumeIsolated { self?.handle(event) }
		}) { monitors.append(global) }
		if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
			MainActor.assumeIsolated { self?.handle(event) }
			return event
		}) { monitors.append(local) }
	}

	func stop() {
		monitors.forEach(NSEvent.removeMonitor)
		monitors = []
		isDown = false
	}

	func handle(_ event: NSEvent) {
		if event.type == .keyDown {
			if event.keyCode == 53 { onEscape() } // kVK_Escape
			if isDown { onChord() }
			return
		}
		guard let key else { return }
		if key == .hyper {
			// Down once ⌘⌥⇧ are all held; up as soon as one is let go. Any other modifier joining is a chord.
			let all = event.modifierFlags.contains(ModifierKey.hyperFlags)
			if all, !isDown {
				isDown = true
				onPress()
			} else if !all, isDown {
				isDown = false
				onRelease()
			} else if isDown, ![55, 54, 58, 61, 56, 60, 59, 62].contains(event.keyCode) {
				// ⌘ ⌥ ⇧ and ⌃ belong to the Hyper key (Raycast can include ⌃); anything else, like fn, is a chord.
				onChord()
			}
			return
		}
		guard event.keyCode == key.keyCode else {
			if isDown { onChord() } // e.g. Shift together with AltGr
			return
		}
		let down = event.modifierFlags.rawValue & key.mask != 0
		if down, !isDown {
			isDown = true
			onPress()
		} else if !down, isDown {
			isDown = false
			onRelease()
		}
	}
}
