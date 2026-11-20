# Function level dead code scan

Periphery 3.8.0 scanned the existing production compiler index for master
049aaeb8 (plus the package-product-only cleanup). The command was:

```sh
periphery scan --project-root <worktree> --index-store-path <worktree>/.build/out \
  --exclude-tests --retain-objc-accessible --retain-swift-ui-previews \
  --disable-update-check --quiet --format json
```

The release ZIP matched GitHub's published SHA-256
`07d4e286e31dd79164df39097e0b59f533c94badbe18158464a455ea88a166d7`.
The raw JSON remains a task artifact, not a repository asset. It contains
1,962 diagnostics, including 481 redundant-public-access warnings and 362
assign-only properties. These are candidates, not 1,962 safe deletions.
Excluding test targets deliberately reports helpers used only by tests; retain
those unless their tests protect behavior that has itself been retired.
Framework-discovered entry points also require manual review.

The confirmed first batch removes `SystemInstall`, `SystemRepair` and
`SystemUninstall`: the registered `system` group contains only `SystemInspect`.
Current setup/uninstall use their separate top-level app-RPC commands. The
old report formatter was reachable only from the three retired commands.
The direct parser test for the unregistered repair command is removed; tests
that reject unavailable system-uninstall CLI requests remain. An unused
spinner message setter is removed as well. No command registration changes.

## Unused diagnostic query path

The November 19 Periphery scan marks DiagnosticsServiceProtocol,
DiagnosticsService and KanataProcessDetector unused. Repository-wide source
usage tracing confirms only their own tests instantiate the service/detector;
there are no production consumers, runtime registrations or Objective-C entry
points. Remove that service path and its dedicated tests and source-file lint
checks, rather than maintaining test-only bypasses in unreachable production
logic. KanataDiagnostic, DiagnosticSeverity and DiagnosticCategory are retained
in Models/KanataDiagnostic.swift because live runtime/recovery/UI code uses them.
Historical ADRs and investigation records retain the old names as history.
