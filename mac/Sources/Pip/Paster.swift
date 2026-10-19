import AppKit
import ApplicationServices

/// Sends a paste shortcut, then attempts to restore the clipboard after a grace period.
@MainActor
enum Paster {
	/// Pasting sends ⌘V to another app, which needs the Accessibility permission.
	static var allowed: Bool { AXIsProcessTrusted() }

	/// Ask for the permission; macOS shows its prompt and lists Pip Voice in System Settings.
	static func requestPermission() {
		let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
		_ = AXIsProcessTrustedWithOptions(options)
	}

	enum Delivery: Equatable {
		/// Paste shortcut sent to an editable field; best-effort clipboard restore is scheduled (not a paste ACK).
		case pasted
		/// Paste shortcut sent, but the target or full clipboard snapshot was uncertain; text stays copied.
		case pastedAndCopied
		/// Nothing editable had focus: the text is on the clipboard only.
		case copied
		/// The origin app, field or selection changed while the command was working.
		case destinationChanged
		/// No Accessibility permission: the text is on the clipboard only.
		case needsPermission
		/// Clipboard write failed: no paste shortcut was sent, and clipboard contents are unspecified.
		case failed
	}

	private static let clipboard = ClipboardTransaction(board: AppKitClipboardBoard(.general)) { delay, completion in
		DispatchQueue.main.asyncAfter(deadline: .now() + delay) { completion() }
	}

	/// Injected effects for the production delivery route; tests never create the live environment.
	struct DeliveryEnvironment {
		let clipboard: ClipboardTransaction
		let hasPermission: () -> Bool
		let focusedTarget: () -> Target
		let postPaste: () -> Void
	}

	private static var liveEnvironment: DeliveryEnvironment {
		DeliveryEnvironment(clipboard: clipboard, hasPermission: { allowed }, focusedTarget: focusedTarget,
			postPaste: { press(keyCode: 9) }) // kVK_ANSI_V; posting is not a paste acknowledgment.
	}

	/// Paste `text` where the cursor is. Unknown/noneditable destinations keep successfully written text copied.
	@discardableResult
	static func copy(_ text: String) -> Bool { clipboard.write(text) != .failed }

	static func deliver(_ text: String) -> Delivery {
		deliver(text, using: liveEnvironment)
	}

	/// The same production decision path, with only its external effects injected.
	static func deliver(_ text: String, using environment: DeliveryEnvironment) -> Delivery {
		guard environment.hasPermission() else {
			return environment.clipboard.write(text) == .failed ? .failed : .needsPermission
		}
		let target = environment.focusedTarget()
		let outcome = environment.clipboard.write(text, restoreAfter: target == .editable ? 0.6 : nil)
		guard outcome != .failed else { return .failed }
		guard target == .editable else { return .copied }
		environment.postPaste()
		return outcome == .restoreScheduled ? .pasted : .pastedAndCopied
	}

	struct Origin {
		let bundleID: String?
		let processID: pid_t?
		let element: AXUIElement?
		let range: CFTypeRef?
		let selection: CFTypeRef?
	}

	/// Capture synchronously at the shortcut press; no focusing apps or keyboard-copy fallback.
	static func captureOrigin() -> Origin {
		let front = NSWorkspace.shared.frontmostApplication
		let element = focusedElement()
		let selected = element.flatMap { attribute($0, kAXSelectedTextAttribute) }
		// Empty selected text alone says nothing about the caret's position.
		let selection = (selected as? String)?.isEmpty == false ? selected : nil
		return Origin(bundleID: front?.bundleIdentifier, processID: front?.processIdentifier, element: element,
			range: element.flatMap { attribute($0, kAXSelectedTextRangeAttribute) },
			selection: selection)
	}

	static func deliverReplacement(_ text: String, origin: Origin?) -> Delivery {
		deliverReplacement(text, originStillFocused: origin.map(originStillFocused) ?? false, using: liveEnvironment)
	}

	static func deliverReplacement(_ text: String, originStillFocused: Bool, using environment: DeliveryEnvironment) -> Delivery {
		guard originStillFocused else {
			guard environment.clipboard.write(text) != .failed else { return .failed }
			return environment.hasPermission() ? .destinationChanged : .needsPermission
		}
		return deliver(text, using: environment)
	}

	private static func originStillFocused(_ origin: Origin) -> Bool {
		let front = NSWorkspace.shared.frontmostApplication
		let element = focusedElement()
		let sameProcess = origin.bundleID != nil && origin.bundleID == front?.bundleIdentifier && origin.processID == front?.processIdentifier
		let sameField = origin.element.flatMap { old in element.map { CFEqual(old, $0) } } ?? false
		func same(_ old: CFTypeRef?, _ attributeName: String) -> Bool? {
			guard let old else { return nil }
			guard let element, let current = attribute(element, attributeName) else { return false }
			return CFEqual(old, current)
		}
		return ReplacementSafety.mayPaste(sameProcess: sameProcess, sameField: sameField,
			sameRange: same(origin.range, kAXSelectedTextRangeAttribute),
			sameSelection: same(origin.selection, kAXSelectedTextAttribute))
	}

	private static func focusedElement() -> AXUIElement? {
		guard allowed else { return nil }
		var focused: CFTypeRef?
		guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focused) == .success,
			let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
		return (focused as! AXUIElement)
	}

	private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
		var value: CFTypeRef?
		guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
		return value
	}

	enum Target: CaseIterable { case editable, notEditable, unknown }

	/// Controls that never take typed text, unless they say otherwise (see `focusedTarget`). Containers such as
	/// AXGroup and AXWebArea are left out: Electron apps report them, or nothing at all, while a text box has focus.
	private static let nonEditableRoles: Set<String> = [
		"AXApplication", "AXWindow", "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
		"AXList", "AXTable", "AXOutline", "AXRow", "AXCell", "AXBrowser", "AXImage", "AXStaticText", "AXLink",
		"AXMenu", "AXMenuItem", "AXMenuBar", "AXMenuBarItem", "AXToolbar", "AXTabGroup", "AXSlider",
		"AXDisclosureTriangle", "AXRadioGroup",
	]
	private static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

	/// Whether the focused element takes text, asked through Accessibility.
	private static func focusedTarget() -> Target {
		let system = AXUIElementCreateSystemWide()
		var focused: CFTypeRef?
		let result = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
		// "Nothing focused" is not trusted: Electron apps say it while their text box has focus.
		guard result == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return .unknown }
		let element = focused as! AXUIElement

		var role: CFTypeRef?
		AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
		let roleName = role as? String
		if let roleName, textRoles.contains(roleName) { return .editable }
		// Web pages and custom views that take text (contenteditable, editors) let the selection be set.
		var settable: DarwinBoolean = false
		if AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &settable) == .success, settable.boolValue {
			return .editable
		}
		if let roleName, nonEditableRoles.contains(roleName) { return .notEditable }
		return .unknown
	}

	/// Send ⌘ plus one key to the app in front.
	static func press(keyCode: CGKeyCode) {
		let source = CGEventSource(stateID: .combinedSessionState)
		for down in [true, false] {
			let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
			event?.flags = .maskCommand
			event?.post(tap: .cghidEventTap)
		}
	}
}
