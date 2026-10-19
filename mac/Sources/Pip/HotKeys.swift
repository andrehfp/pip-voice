import Carbon

/// System-wide shortcuts that report both press and release, so a shortcut can be held down.
/// Carbon hot keys need no Accessibility permission.
@MainActor
final class HotKeys {
	static let shared = HotKeys()
	private var handlers: [UInt32: (Bool) -> Void] = [:]
	private var down: Set<UInt32> = []
	private var refs: [UInt32: EventHotKeyRef] = [:]
	private var installed = false

	/// Returns false when another app already owns the combination.
	func register(id: UInt32, keyCode: Int, modifiers: Int, handler: @escaping (_ pressed: Bool) -> Void) -> Bool {
		installHandler()
		unregister(id: id)
		var ref: EventHotKeyRef?
		let hotKeyID = EventHotKeyID(signature: OSType(0x5049_5021), id: id) // 'PIP!'
		let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
		guard status == noErr, let ref else { return false }
		refs[id] = ref
		handlers[id] = handler
		return true
	}

	func unregister(id: UInt32) {
		if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
		handlers[id] = nil
		down.remove(id)
	}

	fileprivate func fire(id: UInt32, pressed: Bool) {
		// Ignore key repeat while held.
		if pressed { guard down.insert(id).inserted else { return } } else { guard down.remove(id) != nil else { return } }
		handlers[id]?(pressed)
	}

	private func installHandler() {
		guard !installed else { return }
		installed = true
		var types = [
			EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
			EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
		]
		InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
			guard let event else { return OSStatus(eventNotHandledErr) }
			var hotKeyID = EventHotKeyID()
			GetEventParameter(
				event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
				nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
			)
			let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
			MainActor.assumeIsolated { HotKeys.shared.fire(id: hotKeyID.id, pressed: pressed) }
			return noErr
		}, types.count, &types, nil, nil)
	}
}
