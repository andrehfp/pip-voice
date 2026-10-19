import AppKit
import ApplicationServices

private enum Caret {
	@MainActor
	static func rect() -> NSRect? {
		guard AXIsProcessTrusted() else { return nil }
		var focused: CFTypeRef?
		guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focused) == .success,
		      let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
		else { return nil }
		let element = focused as! AXUIElement
		var rangeValue: CFTypeRef?
		guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
		      let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID()
		else { return nil }
		var range = CFRange()
		AXValueGetValue(rangeValue as! AXValue, .cfRange, &range)

		func bounds(_ range: CFRange) -> CGRect? {
			var range = range
			guard let value = AXValueCreate(.cfRange, &range) else { return nil }
			var out: CFTypeRef?
			guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, value, &out) == .success,
			      let out, CFGetTypeID(out) == AXValueGetTypeID()
			else { return nil }
			var rect = CGRect.zero
			AXValueGetValue(out as! AXValue, .cgRect, &rect)
			return rect.height > 0 ? rect : nil
		}
		// An empty range often has no bounds; then use the character before it and stand at its end.
		var rect = bounds(range)
		if rect == nil, range.location > 0, var before = bounds(CFRange(location: range.location - 1, length: 1)) {
			before.origin.x = before.maxX
			before.size.width = 0
			rect = before
		}
		guard let rect, let primary = NSScreen.screens.first else { return nil }
		// Accessibility measures from the top-left of the main screen; AppKit from the bottom-left.
		let flipped = NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
		return NSScreen.screens.contains(where: { $0.frame.intersects(flipped) }) ? flipped : nil
	}
}


private final class VoicePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Read-only feedback: never activates the app or intercepts a click.
@MainActor
final class VoiceOverlay {
    private let panel: VoicePanel
    private let surface = RamsSurfaceView(frame: .zero)
    private let light = RamsLightView(frame: .zero)
    private let bars = RamsLevelBars(frame: .zero)
    private let words = NSTextField(wrappingLabelWithString: "")
    private var dismissal: Task<Void, Never>?
    private var anchor: NSRect?

    init() {
        panel = VoicePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = surface
        surface.addSubview(light)
        surface.addSubview(bars)
        surface.addSubview(words)
        words.font = .systemFont(ofSize: 13)
        words.textColor = Rams.ink
        words.isSelectable = false
        words.maximumNumberOfLines = 0
        words.cell?.lineBreakMode = .byWordWrapping
        words.setAccessibilityLabel("Pip Voice status")
        light.setAccessibilityElement(false)
        bars.setAccessibilityElement(false)
        panel.setAccessibilityLabel("Pip Voice")
    }

    func show(_ text: String, listening: Bool = false, needsAttention: Bool = false) {
        dismissal?.cancel()
        dismissal = nil
        if !panel.isVisible {
            anchor = Caret.rect() ?? NSRect(origin: NSEvent.mouseLocation, size: .zero)
        }
        light.kind = needsAttention ? .need : .work
        bars.isHidden = !listening
        surface.edge = needsAttention ? Rams.acc : Rams.line
        // Only the live tail is bounded; errors retain their complete accessible text.
        words.stringValue = listening && text.count > 280 ? "…" + String(text.suffix(280)) : text
        words.setAccessibilityValue(text)
        layoutAndPosition()
        panel.orderFrontRegardless()
        if needsAttention {
            NSAccessibility.post(element: words, notification: .announcementRequested, userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ])
        }
    }

    func level(_ value: Float) { bars.push(level: value) }

    func flash(_ text: String, needsAttention: Bool = false) {
        show(text, needsAttention: needsAttention)
        light.kind = needsAttention ? .need : .idle
        // Give wrapped errors time to be read; a subsequent show/hide cancels this lifetime.
        let seconds = needsAttention ? max(8, min(30, Double(text.count) / 14)) : 3
        dismissal = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        dismissal?.cancel()
        dismissal = nil
        panel.orderOut(nil)
        anchor = nil
        for _ in 0..<5 { bars.push(level: 0) }
    }

    private func layoutAndPosition() {
        let target = anchor ?? NSRect(origin: NSEvent.mouseLocation, size: .zero)
        let screen = NSScreen.screens.first { $0.frame.contains(target.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let width = min(380, max(160, visible.width - 24))
        let textWidth = width - (bars.isHidden ? 52 : 82)
        words.preferredMaxLayoutWidth = textWidth
        let textHeight = ceil(words.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: textWidth, height: 10000)).height ?? 18)
        let height = min(max(44, textHeight + 24), max(44, visible.height - 24))
        var origin = NSPoint(x: target.minX, y: target.minY - height - 10)
        if origin.y < visible.minY + 12 { origin.y = target.maxY + 10 }
        origin.x = min(max(origin.x, visible.minX + 12), visible.maxX - width - 12)
        origin.y = min(max(origin.y, visible.minY + 12), visible.maxY - height - 12)
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: false)
        light.frame = NSRect(x: 12, y: height - 30, width: 16, height: 16)
        bars.frame = NSRect(x: width - 32, y: height - 29, width: 18, height: 14)
        words.frame = NSRect(x: 38, y: 12, width: textWidth, height: height - 24)
    }
}
