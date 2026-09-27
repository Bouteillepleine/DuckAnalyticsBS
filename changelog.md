## v1.0.1

- dmesg backend is no longer NoMount-only: NoMount, SUSFS `add_open_redirect`, or the
  module mount, picked automatically and pinnable via `feat_peach_backend`
- Dropped four components Play Services re-enables within a minute, so state now holds
- Components PackageManager rejects are remembered and counted as absent
- Sensor appops set at uid scope; the original mode is restored on revert
- A section with no targets on this device no longer reads as partial

## v1.0.0

- GMS telemetry: analytics, Clearcut upload, stats collectors, DropBox reporters
- OxygenOS telemetry: statistics.rom, olc, logkit, metis, stdid, nhs
- peach_v2 roam-stats dmesg flood silenced via NoMount; `hung_task_timeout` 300 s
- Opt in: GMS location reporting, GMS sensor appops, background Wi-Fi scanning
- Every target verified on-device before and after, logged, reverted on uninstall
