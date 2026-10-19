import AppKit

/// A button that shows a shortcut and, when clicked, records a new one: a combination, or a single modifier tapped alone.
@MainActor
final class ShortcutRecorder: NSButton {
	var spec: ShortcutSpec { didSet { refresh() } }
	/// Called with the new shortcut; return a reason to refuse it.
	var onChange: (ShortcutSpec) -> String? = { _ in nil }
	/// Recording started or stopped, so the app can pause its own shortcuts meanwhile.
	var onRecording: (Bool) -> Void = { _ in }
	var onHint: (String) -> Void = { _ in }

	typealias MonitorHandler = (NSEvent) -> NSEvent?
	private let installMonitor: (@escaping MonitorHandler) -> Any?
	private let removeMonitor: (Any) -> Void
	private var monitor: Any?
	private var candidate: ModifierKey?
	/// ⌘⌥⇧ were all held at some point with no other key: a Caps Lock Hyper key tap.
	private var hyperCandidate = false
	private(set) var isRecording = false

	/// Monitor dependencies allow offscreen sessions to use the production event route without live input.
	init(spec: ShortcutSpec,
		installMonitor: @escaping (@escaping MonitorHandler) -> Any? = {
			NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged], handler: $0)
		},
		removeMonitor: @escaping (Any) -> Void = { NSEvent.removeMonitor($0) }) {
		self.spec = spec
		self.installMonitor = installMonitor
		self.removeMonitor = removeMonitor
		super.init(frame: .zero)
		bezelStyle = .rounded
		setButtonType(.momentaryPushIn)
		font = .monospacedSystemFont(ofSize: 13, weight: .medium)
		target = self
		action = #selector(toggle)
		refresh()
	}

	required init?(coder: NSCoder) { fatalError() }

	private func refresh() {
		title = isRecording ? "Press a shortcut…" : spec.label
	}

	/// Stop recording without changing anything.
	func cancel() {
		if isRecording { stop() }
	}

	@objc private func toggle() {
		isRecording ? stop() : start()
	}

	func start() {
		guard !isRecording else { return }
		isRecording = true
		candidate = nil
		hyperCandidate = false
		refresh()
		onRecording(true)
		onHint("Press a combination like ⌥⇧Space, or tap one key alone: AltGr, right ⌘, right ⌃, right ⇧, fn, or a Caps Lock set up as a Hyper key. Delete clears it; Esc keeps the current one.")
		guard isRecording else { return }
		monitor = installMonitor(makeMonitorHandler())
	}

	/// Kept separate so regressions can exercise the real callback without installing a keyboard monitor.
	func makeMonitorHandler() -> MonitorHandler {
		{ [weak self] event in
			// AppKit local monitors run synchronously on the main thread. Cross the isolation
			// boundary with a Sendable decision, never with AppKit's non-Sendable NSEvent.
			let consumed = MainActor.assumeIsolated {
				guard let self, self.isRecording else { return false }
				return self.handle(event) == nil
			}
			// Preserve identity exactly once when passing through; consumed nil must stay nil.
			return consumed ? nil : event
		}
	}

	private func stop() {
		if let monitor { removeMonitor(monitor) }
		monitor = nil
		isRecording = false
		candidate = nil
		hyperCandidate = false
		refresh()
		onRecording(false)
	}

	private func commit(_ new: ShortcutSpec) {
		if let reason = onChange(new) {
			onHint(reason)
		} else {
			spec = new
			onHint("Saved: \(new.label). Tap or hold it.")
		}
		stop()
	}

	/// Returns nil to swallow the event while recording.
	private func handle(_ event: NSEvent) -> NSEvent? {
		if event.type == .keyDown {
			candidate = nil
			hyperCandidate = false
			let plain = event.modifierFlags.intersection([.control, .option, .command]).isEmpty
			if event.keyCode == 53 { // Esc
				stop()
				onHint("Kept \(spec.label).")
			} else if plain, event.keyCode == 51 || event.keyCode == 117 { // Delete, ⌦
				commit(.none)
			} else if let combo = ShortcutSpec.combo(from: event) {
				commit(combo)
			} else {
				onHint("Add ⌃, ⌥ or ⌘ to that key, so it doesn't get in the way of typing.")
			}
			return nil
		}
		// ⌘⌥⇧ together and then released, nothing else pressed: a Caps Lock Hyper key.
		let pressed = event.modifierFlags.intersection([.control, .option, .shift, .command, .function])
		if pressed.contains(ModifierKey.hyperFlags) {
			hyperCandidate = true
			candidate = nil
			return nil
		}
		if hyperCandidate {
			if pressed.isEmpty { commit(.modifier(.hyper)) }
			return nil
		}
		// A modifier alone: pressed and released with no other key in between.
		if let key = ModifierKey.from(keyCode: event.keyCode) {
			if event.modifierFlags.rawValue & key.mask != 0 { candidate = key } else if candidate == key { commit(.modifier(key)) }
		} else if [58, 55, 59, 56].contains(event.keyCode), !pressed.isEmpty {
			onHint("Left-side keys alone are used all the time; use one on the right, or fn.")
		}
		return nil
	}
}
