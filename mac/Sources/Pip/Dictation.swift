import AVFoundation
import Speech

/// Records the microphone while a shortcut is held and transcribes it on this Mac with SpeechAnalyzer.
/// Uses the on-device SpeechTranscriber model, without a cloud recognition fallback.
/// The operating system may download missing language assets before recognition starts.
@MainActor
final class Dictation {
	private let engine = AVAudioEngine()
	private var analyzer: SpeechAnalyzer?
	private var input: AudioInputChannel<AnalyzerInput>?
	private var results: Task<String, Error>?
	private(set) var isRecording = false
	private let session = AudioSession()
	private var configurationObserver: AudioConfigurationObserver<AnalyzerInput>?
	private var tapInstalled = false

	enum Failure: LocalizedError {
		case unsupportedDevice, microphoneDenied, unsupportedLocale(String), noAudioFormat, busy, audioOverflow, audioConversion, audioInterrupted
		var errorDescription: String? {
			switch self {
			case .unsupportedDevice: "On-device speech recognition is not available on this Mac."
			case .microphoneDenied: "Pip Voice cannot use the microphone. Allow it in System Settings → Privacy & Security → Microphone."
			case let .unsupportedLocale(id): "Dictation in \(id) isn't available on this Mac."
			case .noAudioFormat: "No audio format works for dictation."
			case .busy: "The previous dictation is still finishing. Try again shortly."
			case .audioOverflow: "Dictation couldn't keep up with the audio. Nothing was pasted; please try again."
			case .audioInterrupted: "The microphone configuration changed during dictation. Nothing was pasted; please try again."
			case .audioConversion: "Dictation couldn't process the microphone audio. Nothing was pasted; please try again."
			}
		}
	}

	static func microphoneAllowed() async -> Bool {
		switch AVAudioApplication.shared.recordPermission {
		case .granted: return true
		case .denied: return false
		default: return await AVAudioApplication.requestRecordPermission()
		}
	}

	/// Download the language model if it is missing, so the first dictation does not wait for it.
	static func prepare(locale: Locale) async throws {
		guard SpeechTranscriber.isAvailable else { throw Failure.unsupportedDevice }
		guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
			throw Failure.unsupportedLocale(locale.identifier)
		}
		let transcriber = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
		if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
			try await request.downloadAndInstall()
		}
	}

	/// `terms` steer recognition toward the person's own words (names, jargon).
	/// `onPartial` receives the text so far while the person speaks, including words that may still change.
	/// `onLevel` receives the microphone level (0…1) about ten times a second, for the voice meter.
	func start(
		locale: Locale, terms: [String] = [],
		onStatus: @escaping @MainActor (String) -> Void = { _ in },
		onLevel: @escaping @MainActor (Float) -> Void = { _ in },
		onPartial: @escaping (String) -> Void = { _ in },
		onFailure: @escaping @MainActor (Error) -> Void = { _ in }
	) throws -> Task<Void, Error> {
		guard let task = session.start(
			freeze: { [self] cancel in
				stopCapture()
				if cancel { results?.cancel() }
			},
			dispose: { [self] cancel in try await dispose(cancel: cancel) },
			configure: { [self] token in
				try await configure(token: token, locale: locale, terms: terms, onStatus: onStatus, onLevel: onLevel, onPartial: onPartial, onFailure: onFailure)
			}
		) else { throw Failure.busy }
		return task
	}

	private func configure(
		token: UUID, locale: Locale, terms: [String],
		onStatus: @escaping @MainActor (String) -> Void,
		onLevel: @escaping @MainActor (Float) -> Void, onPartial: @escaping (String) -> Void, onFailure: @escaping @MainActor (Error) -> Void
	) async throws {
		let channel = AudioInputChannel<AnalyzerInput>()
		input = channel
		if !session.acceptsCallbacks(token) { channel.finish() }
		guard SpeechTranscriber.isAvailable else { throw Failure.unsupportedDevice }
		onStatus("Waiting for microphone permission…")
		guard await Self.microphoneAllowed() else { throw Failure.microphoneDenied }
		try checkSession(token)
		guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
			throw Failure.unsupportedLocale(locale.identifier)
		}
		try checkSession(token)
		// Progressive: volatile results while speaking, for the live text in the live overlay.
		let transcriber = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
		if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
			try checkSession(token)
			if session.acceptsCallbacks(token) { onStatus("Downloading language model…") }
			try await request.downloadAndInstall()
		}
		try checkSession(token)
		if session.acceptsCallbacks(token) { onStatus("Preparing speech recognition…") }
		guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
			throw Failure.noAudioFormat
		}
		try checkSession(token)

		let analyzer = SpeechAnalyzer(modules: [transcriber])
		self.analyzer = analyzer
		results = Task {
			// Final results are kept; a volatile one is the current guess for the audio after them and gets replaced.
			// The last words can end as volatile, so they count too.
			var final = ""
			var volatile = ""
			for try await result in transcriber.results {
				try Task.checkCancellation()
				guard self.session.owns(token) else { break }
				let text = String(result.text.characters)
				if result.isFinal {
					final = Self.join(final, text)
					volatile = ""
				} else {
					volatile = text
				}
				if self.session.acceptsCallbacks(token) { onPartial(Self.join(final, volatile)) }
			}
			return Self.join(final, volatile)
		}
		// Capture before analyzer preparation so opening words queue instead of disappearing during setup.
		// A stop during earlier permission/asset awaits must still prevent a late tap.
		try session.activateCapture(token) {
			let mic = engine.inputNode
			configurationObserver = AudioConfigurationObserver(
				name: .AVAudioEngineConfigurationChange, object: engine, channel: channel
			) { [weak self] in
				Task { @MainActor [weak self] in
					guard let self, self.session.owns(token) else { return }
					let error = Failure.audioInterrupted
					self.session.fail(token, error: error)
					onFailure(error)
				}
			}
			let micFormat = mic.outputFormat(forBus: 0)
			try checkSession(token)
			guard micFormat.sampleRate > 0, micFormat.channelCount > 0 else { throw Failure.noAudioFormat }
			let converter = AVAudioConverter(from: micFormat, to: format)
			mic.installTap(onBus: 0, bufferSize: 4096, format: micFormat, block: Self.tap(converter: converter, format: format, into: channel, onFailure: { [weak self] reason in
				guard let self, self.session.owns(token) else { return }
				let error = Self.audioFailure(reason)
				self.session.fail(token, error: error)
				onFailure(error)
			}, onLevel: { [weak self] level in
				guard self?.session.acceptsCallbacks(token) == true else { return }
				onLevel(level)
			}))
			tapInstalled = true
			engine.prepare()
			try checkSession(token)
			try engine.start()
			try checkSession(token)
			isRecording = true
		}
		if !terms.isEmpty {
			let context = AnalysisContext()
			context.contextualStrings = [.general: terms]
			try await analyzer.setContext(context)
		}
		try checkSession(token)
		try await analyzer.prepareToAnalyze(in: format)
		try checkSession(token)
		try await analyzer.start(inputSequence: channel.stream)
		try checkSession(token)
	}

	/// Freeze capture before awaiting either startup or final recognition.
	func requestStop() { session.requestStop() }
	func requestCancel() { session.requestCancel() }
	func stop() async throws -> String { try await session.stop() }
	func cancel() async { await session.cancel() }

	/// The reservation is held by AudioSession through the last asynchronous cleanup.
	private func dispose(cancel: Bool) async throws -> String {
		let channel = input
		let analyzer = analyzer
		let results = results
		defer {
			configurationObserver?.invalidate()
			_ = channel?.seal()
			configurationObserver = nil
			input = nil
			self.analyzer = nil
			self.results = nil
		}
		if cancel {
			results?.cancel()
			await analyzer?.cancelAndFinishNow()
			return ""
		}
		do {
			try await analyzer?.finalizeAndFinishThroughEndOfInput()
			let text = try await results?.value ?? ""
			if let reason = channel?.seal() { throw Self.audioFailure(reason) }
			return text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
		} catch {
			results?.cancel()
			await analyzer?.cancelAndFinishNow()
			throw error
		}
	}

	private func stopCapture() {
		isRecording = false
		// Close the producer first: a queued tap cannot append after the user stop.
		input?.finish()
		if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
		engine.stop()
	}

	private func checkSession(_ token: UUID) throws {
		if let reason = input?.failure { throw Self.audioFailure(reason) }
		try session.check(token)
	}
	private static func audioFailure(_ reason: AudioInputChannel<AnalyzerInput>.Failure) -> Failure {
		switch reason {
		case .overflow: .audioOverflow
		case .configurationChanged: .audioInterrupted
		case .conversion, .consumerStopped: .audioConversion
		}
	}

	private static func join(_ head: String, _ tail: String) -> String {
		let tail = tail.trimmingCharacters(in: .whitespaces)
		if head.isEmpty { return tail }
		if tail.isEmpty { return head }
		return "\(head) \(tail)"
	}

	/// The tap runs on the audio thread, so it is built outside the main actor.
	private nonisolated static func tap(
		converter: AVAudioConverter?, format: AVAudioFormat, into channel: AudioInputChannel<AnalyzerInput>,
		onFailure: @escaping @MainActor (AudioInputChannel<AnalyzerInput>.Failure) -> Void,
		onLevel: @escaping @MainActor (Float) -> Void
	) -> AVAudioNodeTapBlock {
		{ buffer, _ in
			let level = loudness(buffer)
			DispatchQueue.main.async { MainActor.assumeIsolated { onLevel(level) } }
			let reason: AudioInputChannel<AnalyzerInput>.Failure?
			if let converted = convert(buffer, with: converter, to: format) {
				reason = channel.push(AnalyzerInput(buffer: converted))
			} else { reason = channel.fail(.conversion) }
			if let reason { DispatchQueue.main.async { MainActor.assumeIsolated { onFailure(reason) } } }
		}
	}

	/// RMS of the first channel mapped from -50…-10 dB to 0…1.
	private nonisolated static func loudness(_ buffer: AVAudioPCMBuffer) -> Float {
		guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
		var sum: Float = 0
		for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
		let rms = (sum / Float(buffer.frameLength)).squareRoot()
		let decibels = 20 * log10(max(rms, 0.000_01))
		return min(max((decibels + 50) / 40, 0), 1)
	}

	private nonisolated static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter?, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
		guard let converter else { return buffer.format == format ? buffer : nil }
		let ratio = format.sampleRate / buffer.format.sampleRate
		let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
		guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
		var consumed = false
		var error: NSError?
		converter.convert(to: output, error: &error) { _, status in
			if consumed {
				status.pointee = .noDataNow
				return nil
			}
			consumed = true
			status.pointee = .haveData
			return buffer
		}
		return error == nil && output.frameLength > 0 ? output : nil
	}
}
