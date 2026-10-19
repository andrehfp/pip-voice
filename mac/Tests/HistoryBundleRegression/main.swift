import Foundation

// This executable runs inside a disposable test bundle, never the live app's domain.
guard let identifier = Bundle.main.bundleIdentifier,
      identifier.hasPrefix("org.pipvoice.tests.history.") else {
    fatalError("History integration tests require their disposable bundle identity")
}
let store = UserDefaults.standard
defer { store.removePersistentDomain(forName: identifier) }
precondition(DictationHistory.items.isEmpty)
DictationHistory.add("Synthetic integration text")
precondition(DictationHistory.items == ["Synthetic integration text"])
precondition(store.stringArray(forKey: "dictationHistory") == DictationHistory.items)
DictationHistory.clear()
precondition(DictationHistory.items.isEmpty)
// Some OS releases reject initWithSuiteName when it equals the main bundle ID.
// Report availability without unwrapping it or reading its contents.
print("Same-bundle named suite available: \(UserDefaults(suiteName: identifier) != nil)")
print("History bundle regressions: 4 checks passed; production defaults in a disposable domain")
