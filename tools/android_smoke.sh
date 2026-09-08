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
  timeout 15 adb shell dumpsys activity activities > "$OUT/activities-final.txt"
  timeout 15 adb shell dumpsys power > "$OUT/power-final.txt"
  timeout 15 adb logcat -d > "$OUT/boot-logcat.txt"
  if [ -n "$PID" ]; then
    timeout 15 adb logcat -d --pid="$PID" > "$OUT/app-logcat.txt"
  fi
  timeout 15 adb exec-out screencap -p > "$OUT/final-screen.png"
}
trap collect EXIT
runtime_ready() {
  local name=$1
  timeout 15 adb shell dumpsys activity services "$PACKAGE" > "$OUT/services-$name.txt" || return 1
  # Require foreground promotion on OUR service, not a different plugin service
  # that happens to appear in the same dumpsys output.
  awk '
    /\* ServiceRecord\{/ { own = /com\.example\.convoy_mesh\/[^ ]*ConvoyForegroundService/ }
    own { print }
  ' "$OUT/services-$name.txt" > "$OUT/owner-$name.txt"
  grep -q 'isForeground=true' "$OUT/owner-$name.txt"
}
wait_for_runtime() {
  local name=$1
  local deadline=$((SECONDS + 120))
  local current
  while (( SECONDS < deadline )); do
    current=$(timeout 10 adb shell pidof "$PACKAGE" | tr -d '\r\n ' || true)
    if [ -n "$current" ]; then
      if [ -n "$PID" ] && [ "$current" != "$PID" ]; then
        echo 'App process restarted during readiness wait' >&2
        return 1
      fi
      PID=$current
      if runtime_ready "$name"; then
        printf '%s\n' "READY: $name pid=$PID elapsed=${SECONDS}s" >> "$OUT/readiness.txt"
        return 0
      fi
    elif [ -n "$PID" ]; then
      echo 'App process died during readiness wait' >&2
      return 1
    fi
    sleep 2
  done
  echo "Runtime did not become ready within the bounded startup deadline: $name" >&2
  return 1
}
assert_runtime() {
  local name=$1
  runtime_ready "$name"
  local current
  current=$(timeout 15 adb shell pidof "$PACKAGE" | tr -d '\r\n ')
  test -n "$current"
  test "$current" = "$PID"
}
launch_app() {
  local name=$1
  # am start -W has its own short first-frame wait. A cold CI emulator may still
  # be extracting the Flutter kernel at that timeout. Request once, then observe
  # the actual live owner with a deadline; do not relaunch or ignore a dead app.
  timeout 30 adb shell am start -n "$PACKAGE/.MainActivity" | tee "$OUT/launch-$name.txt"
  if grep -E 'Error:|Exception' "$OUT/launch-$name.txt"; then return 1; fi
  wait_for_runtime "$name"
}
timeout 90 adb install -r "$APK" | tee "$OUT/install.txt"
grep -q 'Success' "$OUT/install.txt"
for permission in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_SCAN BLUETOOTH_CONNECT BLUETOOTH_ADVERTISE POST_NOTIFICATIONS; do
  timeout 15 adb shell pm grant "$PACKAGE" "android.permission.$permission"
done
timeout 15 adb shell cmd location set-location-enabled true
timeout 15 adb shell input keyevent KEYCODE_WAKEUP
timeout 15 adb shell wm dismiss-keyguard
timeout 15 adb logcat -c
launch_app foreground
assert_runtime foreground
timeout 15 adb exec-out screencap -p > "$OUT/foreground-screen.png"
timeout 15 adb shell input keyevent KEYCODE_HOME
timeout 15 adb shell input keyevent KEYCODE_SLEEP
sleep 2
timeout 15 adb shell dumpsys power > "$OUT/power-screen-off.txt"
grep -Eq 'mWakefulness=(Asleep|Dozing)' "$OUT/power-screen-off.txt"
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
launch_app resumed
sleep 5
assert_runtime resumed
timeout 15 adb logcat -d --pid="$PID" > "$OUT/app-logcat.txt"
if grep -E 'FATAL EXCEPTION|Fatal signal|Unhandled Exception|EXCEPTION CAUGHT BY' "$OUT/app-logcat.txt"; then
  echo 'App exception detected' >&2
  exit 1
fi
printf '%s\n' 'PASS: exact APK installed; process and foreground owner survived verified screen-off; resumed without detected app exception.' > "$OUT/result.txt"
printf '%s\n' 'NOT TESTED: real BLE peer-to-peer, real GNSS error, OEM energy policies, battery endurance.' >> "$OUT/result.txt"
