import AppKit

/// Words dictation should know, from a plain text file the person edits:
/// one term per line to steer recognition, and `wrong => right` lines to fix what it still gets wrong.
enum Vocabulary {
	static let file = FileManager.default.homeDirectoryForCurrentUser
		.appending(path: "Library/Application Support/Pip Voice/vocabulary.txt")

	private static let template = """
	# Pip Voice vocabulary. One term per line; comments and blank lines are ignored.
	# Add names, products or specialist terms to guide local recognition.
	# Example term (uncomment and replace):
	# Example Project
	# Corrections use: heard phrase => intended phrase
	# example mistake => Example Project
	# An empty right side removes the matching phrase.

	"""

	struct Entries {
		var terms: [String] = []
		var fixes: [(wrong: String, right: String)] = []
	}

	static func load() -> Entries {
		createIfMissing()
		guard let text = try? String(contentsOf: file, encoding: .utf8) else { return Entries() }
		return parse(text: text)
	}

	/// Parse without touching the filesystem or preferences.
	static func parse(text: String) -> Entries {
		var entries = Entries()
		for raw in text.components(separatedBy: .newlines) {
			let line = raw.trimmingCharacters(in: .whitespaces)
			if line.isEmpty || line.hasPrefix("#") { continue }
			if let arrow = line.range(of: "=>") {
				let wrong = line[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
				let right = line[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
				if !wrong.isEmpty { entries.fixes.append((wrong, right)) }
				if !right.isEmpty { entries.terms.append(right) }
			} else {
				entries.terms.append(line)
			}
		}
		return entries
	}

	/// Apply the `wrong => right` fixes, matching whole words regardless of case.
	static func fix(_ text: String, with entries: Entries) -> String {
		var out = text
		for (wrong, right) in entries.fixes {
			let pattern = "(?<![\\p{L}\\p{N}])\(NSRegularExpression.escapedPattern(for: wrong))(?![\\p{L}\\p{N}])"
			guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
			out = regex.stringByReplacingMatches(
				in: out, range: NSRange(out.startIndex..., in: out), withTemplate: NSRegularExpression.escapedTemplate(for: right)
			)
		}
		return out
	}

	/// Open the file in the default text editor.
	static func edit() {
		createIfMissing()
		NSWorkspace.shared.open(file)
	}

	/// Create a neutral, comments-only starter file without migrating other apps.
	private static func createIfMissing() {
		guard !FileManager.default.fileExists(atPath: file.path) else { return }
		try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
		try? template.write(to: file, atomically: true, encoding: .utf8)
	}
}

/// The last 20 distinct outputs. The default suite never touches another app's preferences.
enum DictationHistory {
    private static let key = "dictationHistory"
    // The bundle is validated at launch. A suite matching its identifier can return nil.
    // Use the same isolated standard domain as the rest of the app, without a force unwrap.
    private static let defaults = UserDefaults.standard

    static var items: [String] { items(in: defaults) }

    static func items(in store: UserDefaults) -> [String] {
        Array((store.stringArray(forKey: key) ?? []).prefix(20))
    }

    static func add(_ text: String, defaults store: UserDefaults = defaults) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var list = items(in: store).filter { $0 != text }
        list.insert(text, at: 0)
        store.set(Array(list.prefix(20)), forKey: key)
    }

    static func clear(defaults store: UserDefaults = defaults) {
        store.removeObject(forKey: key)
    }
}
