import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else { fatalError("FAIL: \(name)") }
    checks += 1
}
let empty = Vocabulary.parse(text: " \n# comment\r\n\t# another\n")
check(empty.terms.isEmpty && empty.fixes.isEmpty, "comments and whitespace")
let entries = Vocabulary.parse(text: "  Example Project \r\nmisheard => Correct Name\nremove =>\n=> ignored\n")
check(entries.terms == ["Example Project", "Correct Name", "ignored"], "trim terms and correction hints")
check(entries.fixes.count == 2, "ignore empty left side")
check(entries.fixes[1].right.isEmpty, "empty replacement")
check(Vocabulary.fix("MISHEARD, misheardly; remove!", with: entries) == "Correct Name, misheardly; !", "case and boundaries")
let unicode = Vocabulary.parse(text: "café => coffee\nc++ => C Plus Plus\ncash => $5\\value")
check(Vocabulary.fix("CAFÉ caféine 2café café2", with: unicode) == "coffee caféine 2café café2", "unicode boundaries")
check(Vocabulary.fix("c++ and cash", with: unicode) == "C Plus Plus and $5\\value", "literal pattern and replacement")
check(Vocabulary.fix("unchanged", with: empty) == "unchanged", "empty fixes")
check(Vocabulary.parse(text: "a => b => c").fixes.first?.right == "b => c", "split first arrow only")
let suite = "org.pipvoice.tests.vocabulary.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
check(DictationHistory.items(in: defaults).isEmpty, "fresh isolated history")
for number in 0..<25 { DictationHistory.add("Item \(number)", defaults: defaults) }
check(DictationHistory.items(in: defaults).count == 20, "history limit")
check(DictationHistory.items(in: defaults).first == "Item 24", "newest first")
check(DictationHistory.items(in: defaults).last == "Item 5", "oldest evicted")
DictationHistory.add("Item 10", defaults: defaults)
check(DictationHistory.items(in: defaults).first == "Item 10", "duplicate promoted")
check(DictationHistory.items(in: defaults).filter { $0 == "Item 10" }.count == 1, "distinct history")
DictationHistory.add(" \n", defaults: defaults)
check(DictationHistory.items(in: defaults).count == 20, "ignore empty dictation")
defaults.set(true, forKey: "unrelated")
DictationHistory.clear(defaults: defaults)
check(DictationHistory.items(in: defaults).isEmpty, "clear history")
check(defaults.bool(forKey: "unrelated"), "clear preserves other settings")
check(Vocabulary.file.path.hasSuffix("Application Support/Pip Voice/vocabulary.txt"), "isolated vocabulary path")
print("Vocabulary regressions: \(checks) checks passed")
