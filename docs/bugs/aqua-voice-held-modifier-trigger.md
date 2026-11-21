# Aqua Voice ends a held Control+Shift trigger with KeyPath active

Aqua Voice's left Control + left Shift hold-to-record shortcut stopped while
both keys were held. On the MacBook Air, the issue reproduced with only KeyPath's
default macOS Function Keys collection enabled. Pausing KeyPath restored a
3.7-second hold. Resuming it brought back the immediate release.

A modifier-only trace recorded the two hardware presses 0.26 ms apart. The
session event stream then received a replacement Control-only event from
KeyPath after both keys were physically down, followed by the Shift event
about 9 ms later. This confirms the event ordering. Aqua Voice's own release
predicate was not inspected.

The session bridge now preserves native events for implicit identity modifiers
in a single stateless layer, including the default Function Keys profile.
Explicit modifier inputs, competing modifier outputs, and configurations with
stateful actions keep their normal engine routing. The bridge reapplies this
policy when Kanata reloads the config. The tap keeps each in-flight modifier
press and release on the same route across a reload.

Regression tests cover the generated Function Keys config, deliberate modifier
inputs and outputs, tap-hold and layer dependencies, and live reload in both
directions. The Swift tests replay the four observed hardware flag values and
check modifier ownership across a reload. For live acceptance, hold left Control + left Shift with KeyPath
running, check that Aqua Voice stays active until release, then check that it
can paste the transcript into a scratch document.
