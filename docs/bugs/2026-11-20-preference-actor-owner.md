# Observable preference ownership

PreferencesService had an unchecked Sendable conformance justified by its
thread-safe UserDefaults store. Its observable Swift properties and persistence
suppression flags are separate mutable state: the store's synchronization does
not protect them. The service now has a checked MainActor owner, covering
initialization, mutation, observation and the matching persistence writes.

The immutable preference key, value-clamping functions and independent defaults
lookup remain nonisolated for configuration and CLI callers. No preference key,
default value, decoding rule or test-mode safeguard changed.

The unused preferencesService EnvironmentKey was a second construction path.
Repository searches found only its two injection sites and no readers; views
already receive preferences through ServiceContainer. Remove that key and its
two writes instead of adding a new actor escape hatch. ServiceContainer's
injected preference instance remains the view dependency.

Existing regressions passed: 17 preference tests, 49 persistence tests,
16 unmapped-layer style tests, 31 pack transaction tests and 14 durable recovery
tests. All 127 checks passed with zero Swift warnings. They cover the preserved
preference behavior and configuration integration, not live host deployment.
The final integrated gate and review results are recorded in the PR.
