# DuckAnalyticsBS

Google and OxygenOS analytics off, dmesg quiet. Every target is verified to exist on
*this* device before it is touched, verified again after, logged, and reverted on uninstall.

absorbs the standalone `peach_roamstats_quiet` module — installing this supersedes it
automatically.

## Why the original design was dropped

The upstream module duty-cycled GMS: 180 s of `RUN_IN_BACKGROUND=ignore` +
`restricted` bucket + cancelled jobs, then a 25 s window with two broadcast "heartbeats"
to pull queued FCM pushes. Measured on an OP15 (CPH2747, OOS 16.0.10.601, SDK 36,
6 h 39 m on battery, 657 mAh drain):

| Claim | Measured |
|---|---|
| GMS background execution is the drain | GMS: **17 alarm wakeups**, **0 ms** mobile radio active |
| All-app wakelock cost | **8.66 mAh of 657** — 1.3% of drain |
| Heartbeat broadcasts pull pushes | `cmd package query-receivers -a …MCS_HEARTBEAT` → **No receivers found** (both actions) |
| `am set-standby-bucket gms restricted` | bucket stays **5 (EXEMPTED)** — GMS is system-allowlisted, the call is a silent no-op |
| `deviceidle whitelist -gms` strips Doze exemption | `system,com.google.android.gms,10129` — it is on the **system** allowlist; only `sys-whitelist -` touches that |
| `pm revoke` of GMS location/sensors | flags are `SYSTEM_FIXED|GRANTED_BY_DEFAULT` → revoke throws, always a no-op |
| `resetprop device_idle_constants` | not a property; the global setting reads `null` and the `device_idle` DeviceConfig namespace is empty |
| 6 OxygenOS telemetry packages | **4 of 6 do not exist** on OOS16 (healthcheck, analytics, qualityprotect, crashbox) |
| `.measurement.AppMeasurementReceiver`, `.analytics.AnalyticsService` | not declared in GMS 26.37.30; real names are `.measurement.PackageMeasurementReceiver` and `.analytics.service.AnalyticsService` |

It also applied `netpolicy restrict-background-blacklist` once at boot and never lifted it,
so GMS had no background network during its own 25 s "sync" window — the two halves
cancelled out. And the whole thing ran after a bash array (`RECEIVERS=(…)`), which is a
syntax error under busybox ash — the shell `ksud` and `apd` use for module scripts
(`ASH_STANDALONE`, `/data/adb/ksu/bin/busybox`). On KernelSU and APatch the script died at
that line, so only the OxygenOS half ever ran.

So: no duty-cycle loop, no standby-bucket calls, no `pm revoke`, no netpolicy, no
phantom broadcasts, no `device_idle_constants`. What is left is what measurably exists.

## What it actually does

### On by default

- **GMS telemetry** — disables 11 declared components: Analytics receiver/service/task,
  Clearcut `QosUploaderService`, `PlatformStatsCollectorService`, `GmsCoreStatsService`,
  both `DropBoxEntryAdded*`, `PackageMeasurement*`, `UsageReportingIntentService`.
  `MeasurementBrokerService` is deliberately left alone — apps' Firebase SDK binds to it.
  `.checkin.*` is left alone — that is device registration.
- **OxygenOS telemetry** — disables `com.oplus.statistics.rom`, `olc`, `logkit`, `metis`,
  `stdid`, `nhs`. Verified present on OOS16; log/analytics/identifier services only,
  nothing in a boot or scheduling path.
- **dmesg quiet** (absorbed `peach_roamstats_quiet`) — appends `groam_info_stats_num=0`
  above the `END` marker of this device's own `/vendor/etc/wifi/peach_v2/WCNSS_qcom_cfg.ini`
  and serves it through NoMount's hookless VFS. Kills the
  `extract_roam_trigger_stats_tlv` flood (was ~88% of the dmesg buffer). Inert no-op on
  non-peach devices: the zip ships no INI, `customize.sh` generates it from the live one.
- **hung_task timeout** — 300 s instead of 60 s. The D-state threads
  (`adci`, `osml`, `hfi`, `soccp`, `zram_comp`) are benign idle waiters that
  `oplus_bsp_dfr_hung_task_enhance` flags every 60 s. `panic` stays 0, so a genuine
  multi-minute hang is still reported.

### Opt in — these change behaviour

- **GMS location reporting** — 5 ULR / semantic-location upload components (4 of the 5
  are declared on GMS 26.37.30; the absent one is skipped and logged). Kills Location
  History and Timeline.
- **GMS sensors** — `ACTIVITY_RECOGNITION` and `BODY_SENSORS` appops to `ignore`
  (appops work where `pm revoke` cannot, and are reversible). Measured: GMS held
  sensor 172 for **3 h 18 m blamed / 5 h 19 m real** in 6 h 39 m. Stops step counting
  and motion detection.
- **Background Wi-Fi scanning** — `wifi_scan_always_enabled=0`. Feeds GMS's
  `CollectionLib-SigCollector` (5 m 21 s of wakelock, the 4th largest on the device)
  and `NetworkLocationScanner`. Costs network-location accuracy.

### Deliberately not touched

Bluetooth. GMS holds two permanent BLE scan clients — `nearby_fast_pair` and
`nearby_presence` — plus `OfflineBeaconService_Persistent`, together **2 h 30 m of blamed
scan in 6 h 39 m** inside a `bluetooth: 95.5 mAh` bucket (14.5% of drain). That is by far
the largest single win available, and it is left alone by choice: switching it off costs
Fast Pair popups, Nearby Presence, and Find My Device network participation.

Also not touched: GMS background execution, standby bucket, netpolicy, runtime
permissions, Doze allowlists, FCM. Push notifications behave exactly as stock.

**Honest expectation:** with Bluetooth excluded, the measurable saving here is small —
low single-digit percent. The larger value is that it stops *doing harm*: no throttled
GMS, no permanently blocked background data, no delayed pushes, and a clean revert.
Your own top wakelock holders are apps, not GMS: `AudioMix` 12 m 58 s,
`com.airfrance.android.dinamoprd` 7 m 02 s, `com.community.mbox.in` 6 m 49 s,
then GMS at 5 m 21 s.

## Verification model

Nothing is assumed:

- A per-GMS-version cache of GMS's declared components is built with `pm dump`; a target
  that is not in it is skipped and logged, never blindly `pm disable`d. That list is not
  stable — successive `pm dump` runs on the same GMS build returned 945, 928 and 946
  entries, because Chimera loads modules dynamically. So "already disabled" is always
  checked *before* "does it exist", and the denominator counts a target as present if it
  exists **or** is already disabled. Otherwise a disabled component that dropped out of
  the dump reads as `11/10`.
- Every change is read back (`disabledComponents` for components, `pm list packages -d`
  for packages, `cmd appops get` for appops). Success or failure is logged either way.
- Nothing is silenced with `2>/dev/null` and then assumed to have worked.
- Anything already disabled by something else is recorded as such and **not** re-enabled
  on uninstall.
- `state` lists exactly what this module changed. It is the revert list.

## Uninstall

`uninstall.sh` runs at boot in post-fs-data, where `pm` does not exist yet, so a blind
revert there would silently fail. Instead it copies `state` to
`/data/adb/duckanalyticsbs.revert` and drops a self-contained one-shot script in
`/data/adb/service.d/`, which waits for `sys.boot_completed`, reverts every recorded
change, logs to `/data/adb/duckanalyticsbs-revert.log`, and deletes itself.

To revert without waiting for a reboot, use **Revert all** in the WebUI, or:

```bash
su -c "sh /data/adb/modules/duckanalyticsbs/ctl.sh revert"
```

State lives outside the module directory precisely so a module *upgrade* cannot orphan it:

| path | mode | purpose |
|---|---|---|
| `duckanalyticsbs.conf` | 0644 | feature flags |
| `duckanalyticsbs.state` | 0600 | the revert list — what this module changed |
| `duckanalyticsbs.log` | 0644 | every apply/revert, with per-target success or failure |
| `duckanalyticsbs.comps` + `.compsver` | 0644 | component cache, keyed to the GMS version |

all under `/data/adb/`. Only uninstall removes `state`, and only after handing it to the
boot helper.

## CLI

```bash
su -c "sh /data/adb/modules/duckanalyticsbs/ctl.sh report"
su -c "sh /data/adb/modules/duckanalyticsbs/ctl.sh status"
su -c "sh /data/adb/modules/duckanalyticsbs/ctl.sh apply"
su -c "sh /data/adb/modules/duckanalyticsbs/ctl.sh revert"
su -c "sh /data/adb/modules/duckanalyticsbs/ctl.sh on gmsloc"
su -c "sh /data/adb/modules/duckanalyticsbs/ctl.sh off gmstel"
su -c "sh /data/adb/modules/duckanalyticsbs/ctl.sh log"
```

Features: `peach gmstel oostel gmsloc gmsact wifiscan hungtask all`

## Build

`./build.sh` packages from an explicit file manifest and refuses to produce a zip if any
shipped file contains CRLF or fails `dash -n`. Both gates exist because of real failures:
the module this replaces shipped CRLF in every script and a bash array that busybox ash
cannot parse. Packaging with `zip -r .` instead of a manifest once swept a stray editor
artifact into the zip, which then broke `set_perm_recursive` on-device — hence the
manifest.

The zip ships no `vendor/` tree; `customize.sh` creates it only on a peach_v2 device,
generated from that device's own INI.

## Compatibility

Targets verified on OP15 / CPH2747 / OxygenOS 16 / SDK 36 / KernelSU-Next.
POSIX sh only — no arrays, no bashisms, runs under busybox ash and mksh alike.
The dmesg feature needs NoMount (`meta-nomount`) for its hookless VFS; without it that
one feature stays inert and the rest work normally.

## Credits

the module it was forked from.
