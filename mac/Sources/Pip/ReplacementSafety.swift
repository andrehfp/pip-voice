import Foundation

/// Replacements need positive evidence of the original destination, not merely an editable current field.
enum ReplacementSafety {
	static func mayPaste(sameProcess: Bool, sameField: Bool, sameRange: Bool?, sameSelection: Bool?) -> Bool {
		guard sameProcess, sameField else { return false }
		if sameRange == false || sameSelection == false { return false }
		// If the app exposes neither caret/selection range nor selected text, do not guess.
		return sameRange == true || sameSelection == true
	}
}
