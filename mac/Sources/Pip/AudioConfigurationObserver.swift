import Foundation

/// Observe only this engine/session. Persist the failure on the posting thread, before hopping to the UI.
/// The channel remains failure-aware after input finish, until final recognition seals it.
final class AudioConfigurationObserver<Value> {
	private let center: NotificationCenter
	private var observer: NSObjectProtocol?
	init(
		center: NotificationCenter = .default, name: Notification.Name, object: AnyObject,
		channel: AudioInputChannel<Value>, onFailure: @escaping @Sendable () -> Void
	) {
		self.center = center
		observer = center.addObserver(forName: name, object: object, queue: nil) { _ in
			guard channel.fail(.configurationChanged) != nil else { return }
			onFailure()
		}
	}
	func invalidate() {
		if let observer { center.removeObserver(observer) }
		observer = nil
	}
	deinit { invalidate() }
}
