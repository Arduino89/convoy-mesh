#!/usr/bin/env bash
set -euo pipefail
APK=${1:?APK path required}
PACKAGE=com.example.convoy_mesh
OUT=emulator-artifacts
mkdir -p "$OUT"
PID=''
collect() {
  set +e
  timeout 15 adb shell dumpsys activity services "$PACKAGE" > "$OUT/services-final.txt"
  timeout 15 adb shell dumpsys power > "$OUT/power-final.txt"
  if [ -n "$PID" ]; then timeout 15 adb logcat -d --pid="$PID" > "$OUT/app-logcat.txt";
  else timeout 15 adb logcat -d > "$OUT/boot-logcat.txt"; fi
  timeout 15 adb exec-out screencap -p > "$OUT/final-screen.png"
}
trap collect EXIT
assert_runtime() {
  local name=$1
  timeout 15 adb shell dumpsys activity services "$PACKAGE" > "$OUT/services-$name.txt"
  grep -q 'ConvoyForegroundService' "$OUT/services-$name.txt"
  grep -q 'isForeground=true' "$OUT/services-$name.txt"
  local current
  current=$(timeout 15 adb shell pidof "$PACKAGE" | tr -d '\r\n ')
  test -n "$current"
  test "$current" = "$PID"
}
timeout 90 adb install -r "$APK" | tee "$OUT/install.txt"
grep -q 'Success' "$OUT/install.txt"
for permission in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_SCAN BLUETOOTH_CONNECT BLUETOOTH_ADVERTISE POST_NOTIFICATIONS; do
  timeout 15 adb shell pm grant "$PACKAGE" "android.permission.$permission"
done
timeout 15 adb shell cmd location set-location-enabled true
timeout 15 adb logcat -c
timeout 30 adb shell am start -W -n "$PACKAGE/.MainActivity" | tee "$OUT/launch.txt"
grep -q 'Status: ok' "$OUT/launch.txt"
sleep 20
PID=$(timeout 15 adb shell pidof "$PACKAGE" | tr -d '\r\n ')
assert_runtime foreground
timeout 15 adb shell input keyevent KEYCODE_HOME
timeout 15 adb shell input keyevent KEYCODE_SLEEP
sleep 2
timeout 15 adb shell dumpsys power > "$OUT/power-screen-off.txt"
# A 70-second wait exceeds the native owner lease. A dead Dart owner must fail.
# Synthetic GPS injection exercises the platform provider, not real GNSS accuracy.
for i in $(seq 1 14); do
  latitude=$(python3 -c "print(45.0 + $i * 0.000005)")
  timeout 10 adb emu geo fix 10.0 "$latitude" >> "$OUT/gps-injection.txt" 2>&1
  sleep 5
done
assert_runtime screen-off
timeout 15 adb shell input keyevent KEYCODE_WAKEUP
timeout 15 adb shell wm dismiss-keyguard
timeout 30 adb shell am start -W -n "$PACKAGE/.MainActivity" >> "$OUT/launch.txt"
sleep 5
assert_runtime resumed
timeout 15 adb logcat -d --pid="$PID" > "$OUT/app-logcat.txt"
if grep -E 'FATAL EXCEPTION|Fatal signal|Unhandled Exception|EXCEPTION CAUGHT BY' "$OUT/app-logcat.txt"; then
  echo 'App exception detected' >&2
  exit 1
fi
printf '%s\n' 'PASS: exact APK installed; process and foreground owner survived screen-off; resumed without detected app exception.' > "$OUT/result.txt"
printf '%s\n' 'NOT TESTED: real BLE peer-to-peer, real GNSS error, OEM energy policies, battery endurance.' >> "$OUT/result.txt"
