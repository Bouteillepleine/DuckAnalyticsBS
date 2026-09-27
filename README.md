# DuckAnalyticsBS

Turns off Google Play Services and OxygenOS analytics, and silences the peach_v2 Wi-Fi dmesg flood.
Magisk / KernelSU / APatch, with a WebUI. The dmesg part serves its patched INI through NoMount
or SUSFS open-redirect when either is present, otherwise through the module mount on reboot.

Every target is checked to exist on *this* device before it is touched, verified after, logged, and
reverted on uninstall. Anything already disabled by something else is never claimed.

**On by default** — GMS telemetry components · OxygenOS telemetry packages
(`statistics.rom olc logkit metis stdid nhs`) · peach_v2 roam-stats · `hung_task_timeout` 300 s

**Opt in** — GMS location reporting (kills Timeline) · GMS sensor appops (kills step counting) ·
background Wi-Fi scanning

```bash
sh /data/adb/modules/duckanalyticsbs/ctl.sh report
sh /data/adb/modules/duckanalyticsbs/ctl.sh revert
sh /data/adb/modules/duckanalyticsbs/ctl.sh on|off  peach|gmstel|oostel|gmsloc|gmsact|wifiscan|hungtask
```

Does not touch Bluetooth, FCM, background execution, standby buckets or runtime permissions.
State lives in `/data/adb/duckanalyticsbs.{conf,state,log}`; `feat_peach_backend=auto|nomount|susfs|mount`
pins the dmesg backend. Build with `./build.sh`.
