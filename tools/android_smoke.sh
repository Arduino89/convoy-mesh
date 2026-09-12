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
  awk '
    /\* ServiceRecord\{/ { own = /com\.example\.convoy_mesh\/[^ ]*ConvoyForegroundService/ }
    own { print }
  ' "$OUT/services-$name.txt" > "$OUT/owner-$name.txt"
  grep -q 'isForeground=true' "$OUT/owner-$name.txt"
}
wait_for_process() {
  local name=$1
  local deadline=$((SECONDS + 90))
  local current
  while (( SECONDS < deadline )); do
    current=$(timeout 10 adb shell pidof "$PACKAGE" | tr -d '\r\n ' || true)
    if [ -n "$current" ]; then
      if [ -n "$PID" ] && [ "$current" != "$PID" ]; then
        echo 'App process restarted during process wait' >&2
        return 1
      fi
      PID=$current
      printf '%s\n' "PROCESS: $name pid=$PID elapsed=${SECONDS}s" >> "$OUT/readiness.txt"
      return 0
    fi
    sleep 2
  done
  echo "App process did not become ready: $name" >&2
  return 1
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
assert_no_runtime() {
  local name=$1
  if runtime_ready "$name"; then
    echo "Foreground runtime unexpectedly active: $name" >&2
    return 1
  fi
  local current
  current=$(timeout 15 adb shell pidof "$PACKAGE" | tr -d '\r\n ')
  test -n "$current"
  test "$current" = "$PID"
}
launch_app_process() {
  local name=$1
  timeout 30 adb shell am start -n "$PACKAGE/.MainActivity" | tee "$OUT/launch-$name.txt"
  if grep -E 'Error:|Exception' "$OUT/launch-$name.txt"; then return 1; fi
  wait_for_process "$name"
}
launch_app_runtime() {
  local name=$1
  timeout 30 adb shell am start -n "$PACKAGE/.MainActivity" | tee "$OUT/launch-$name.txt"
  if grep -E 'Error:|Exception' "$OUT/launch-$name.txt"; then return 1; fi
  wait_for_runtime "$name"
}
wait_and_tap_text() {
  local text=$1
  local name=$2
  local deadline=$((SECONDS + 60))
  while (( SECONDS < deadline )); do
    timeout 15 adb shell uiautomator dump /sdcard/convoy-ui.xml >/dev/null 2>&1 || true
    timeout 15 adb shell cat /sdcard/convoy-ui.xml > "$OUT/ui-$name.xml" 2>/dev/null || true
    local bounds
    bounds=$(python3 - "$OUT/ui-$name.xml" "$text" <<'PY'
import re, sys, xml.etree.ElementTree as ET
path, wanted = sys.argv[1], sys.argv[2]
try:
    root = ET.parse(path).getroot()
except Exception:
    raise SystemExit(1)
for node in root.iter('node'):
    text = node.attrib.get('text', '')
    desc = node.attrib.get('content-desc', '')
    if text == wanted or desc == wanted or desc.startswith(wanted + '\n'):
        m = re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.attrib.get('bounds',''))
        if m:
            x1,y1,x2,y2 = map(int,m.groups())
            print((x1+x2)//2, (y1+y2)//2)
            raise SystemExit(0)
raise SystemExit(1)
PY
) || true
    if [ -n "$bounds" ]; then
      read -r x y <<< "$bounds"
      timeout 15 adb shell input tap "$x" "$y"
      printf '%s\n' "TAP: $text at $x,$y" >> "$OUT/readiness.txt"
      return 0
    fi
    sleep 2
  done
  echo "UI control not found: $text" >&2
  return 1
}
wait_and_tap_location_permission() {
  local name=$1
  local deadline=$((SECONDS + 60))
  while (( SECONDS < deadline )); do
    timeout 15 adb shell uiautomator dump /sdcard/convoy-permission.xml >/dev/null 2>&1 || true
    timeout 15 adb shell cat /sdcard/convoy-permission.xml > "$OUT/ui-$name.xml" 2>/dev/null || true
    local bounds
    bounds=$(python3 - "$OUT/ui-$name.xml" <<'PY2'
import re, sys, xml.etree.ElementTree as ET
path = sys.argv[1]
try:
    root = ET.parse(path).getroot()
except Exception:
    raise SystemExit(1)
preferred = []
fallback = []
for node in root.iter('node'):
    rid = node.attrib.get('resource-id','')
    text = node.attrib.get('text','').lower()
    target = None
    if rid.endswith('permission_allow_foreground_only_button'):
        target = preferred
    elif ('while using' in text or 'durante l\'uso' in text) and 'allow' in text or 'mentre usi' in text:
        target = fallback
    if target is not None:
        m = re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.attrib.get('bounds',''))
        if m:
            target.append(tuple(map(int,m.groups())))
for candidates in (preferred, fallback):
    if candidates:
        x1,y1,x2,y2 = candidates[0]
        print((x1+x2)//2, (y1+y2)//2)
        raise SystemExit(0)
raise SystemExit(1)
PY2
) || true
    if [ -n "$bounds" ]; then
      read -r x y <<< "$bounds"
      timeout 15 adb shell input tap "$x" "$y"
      printf '%s\n' "TAP: location permission at $x,$y" >> "$OUT/readiness.txt"
      return 0
    fi
    sleep 2
  done
  echo 'Location permission request not shown on clean install' >&2
  return 1
}

capture_diag() {
  local name=$1
  timeout 15 adb shell run-as "$PACKAGE" find . -type f > "$OUT/diag-files-$name.txt"
  local path
  path=$(tr -d '\r' < "$OUT/diag-files-$name.txt" | grep -E 'convoy-test-.*\.jsonl$' | tail -n 1 || true)
  if [ -z "$path" ]; then
    echo "Diagnostic JSONL not found: $name" >&2
    return 1
  fi
  timeout 15 adb shell run-as "$PACKAGE" cat "$path" > "$OUT/diag-$name.jsonl"
  test -s "$OUT/diag-$name.jsonl"
}
count_matches() {
  local pattern=$1
  local file=$2
  grep -c "$pattern" "$file" 2>/dev/null || true
}

timeout 90 adb install -r "$APK" | tee "$OUT/install.txt"
grep -q 'Success' "$OUT/install.txt"
# Grant Bluetooth first but deliberately leave location ungranted. Nearby itself
# must request location on a clean Android 12+ install because Convoy uses BLE
# observations as proximity/location evidence and does not declare neverForLocation.
for permission in BLUETOOTH_SCAN BLUETOOTH_CONNECT BLUETOOTH_ADVERTISE POST_NOTIFICATIONS; do
  timeout 15 adb shell pm grant "$PACKAGE" "android.permission.$permission"
done
timeout 15 adb shell pm revoke "$PACKAGE" android.permission.ACCESS_FINE_LOCATION >/dev/null 2>&1 || true
timeout 15 adb shell pm revoke "$PACKAGE" android.permission.ACCESS_COARSE_LOCATION >/dev/null 2>&1 || true
timeout 15 adb shell cmd location set-location-enabled true
timeout 15 adb shell input keyevent KEYCODE_WAKEUP
timeout 15 adb shell wm dismiss-keyguard
timeout 15 adb logcat -c

# Opening the app must request location before Nearby discovery, then remain a
# lightweight process with no foreground service.
launch_app_process nearby-first-run
wait_and_tap_location_permission location-first-run
sleep 3
timeout 15 adb shell pm check-permission android.permission.ACCESS_FINE_LOCATION "$PACKAGE" \
  > "$OUT/location-permission.txt"
grep -q 'granted' "$OUT/location-permission.txt"
assert_no_runtime nearby
timeout 15 adb exec-out screencap -p > "$OUT/nearby-screen.png"

# A diagnostic session may begin BEFORE an outing and must span the transition.
wait_and_tap_text 'Test log' open-test-log
wait_and_tap_text 'Avvia test • max 4 min' start-diagnostic
sleep 2
capture_diag nearby-test
grep -q '"category":"session","event":"start"' "$OUT/diag-nearby-test.jsonl"
if grep -q '"category":"session","event":"stop"' "$OUT/diag-nearby-test.jsonl"; then
  echo 'Diagnostic session stopped unexpectedly in Nearby mode' >&2
  exit 1
fi

# Explicitly start an outing through the real UI. Only now must FGS appear.
wait_and_tap_text 'Avvia uscita' start-outing
wait_for_runtime outing
assert_runtime outing
timeout 15 adb exec-out screencap -p > "$OUT/outing-screen.png"

# Give the estimator a stationary acquisition cluster before screen-off.
for i in 1 2 3; do
  timeout 10 adb emu geo fix 10.0 45.0 >> "$OUT/gps-injection.txt" 2>&1
  sleep 5
done
capture_diag before-screen-off
BASE_FIXES=$(count_matches '"category":"gps","event":"fix"' "$OUT/diag-before-screen-off.jsonl")
BASE_TRACK=$(count_matches '"track_added":true' "$OUT/diag-before-screen-off.jsonl")
BASE_LINES=$(wc -l < "$OUT/diag-before-screen-off.jsonl")

timeout 15 adb shell input keyevent KEYCODE_HOME
timeout 15 adb shell input keyevent KEYCODE_SLEEP
sleep 2
timeout 15 adb shell dumpsys power > "$OUT/power-screen-off.txt"
grep -Eq 'mWakefulness=(Asleep|Dozing)' "$OUT/power-screen-off.txt"

# Keep a physically plausible slow walk (~2.2 m / 5 s) while the screen is off.
# This proves more than process survival: GPS fixes must continue and the local
# filtered trail must gain at least one point for future HISTORY catch-up.
for i in $(seq 1 14); do
  latitude=$(python3 -c "print(45.0 + $i * 0.00002)")
  timeout 10 adb emu geo fix 10.0 "$latitude" >> "$OUT/gps-injection.txt" 2>&1
  sleep 5
done
assert_runtime screen-off
sleep 2
capture_diag screen-off
AFTER_FIXES=$(count_matches '"category":"gps","event":"fix"' "$OUT/diag-screen-off.jsonl")
AFTER_TRACK=$(count_matches '"track_added":true' "$OUT/diag-screen-off.jsonl")
if [ "$AFTER_FIXES" -le "$BASE_FIXES" ]; then
  echo "No new GPS fixes while screen was off ($BASE_FIXES -> $AFTER_FIXES)" >&2
  exit 1
fi
if [ "$AFTER_TRACK" -le "$BASE_TRACK" ]; then
  echo "Local trail did not grow while screen was off ($BASE_TRACK -> $AFTER_TRACK)" >&2
  exit 1
fi
printf '%s\n' "SCREEN_OFF_EVIDENCE: gps_fix=$BASE_FIXES->$AFTER_FIXES track_added=$BASE_TRACK->$AFTER_TRACK" >> "$OUT/readiness.txt"

timeout 15 adb shell input keyevent KEYCODE_WAKEUP
timeout 15 adb shell wm dismiss-keyguard
launch_app_runtime resumed
sleep 5
assert_runtime resumed

# Ending the outing must NOT end the diagnostic session.
capture_diag before-outing-stop
STOP_BASE_LINES=$(wc -l < "$OUT/diag-before-outing-stop.jsonl")
wait_and_tap_text 'Uscita attiva • Termina uscita' stop-outing
sleep 8
assert_no_runtime after-outing-stop
capture_diag after-outing-stop
if grep -q '"category":"session","event":"stop"' "$OUT/diag-after-outing-stop.jsonl"; then
  echo 'Diagnostic session was coupled to Termina uscita' >&2
  exit 1
fi
tail -n +$((STOP_BASE_LINES + 1)) "$OUT/diag-after-outing-stop.jsonl" > "$OUT/diag-after-stop-tail.jsonl"
grep -q '"outing_active":false' "$OUT/diag-after-stop-tail.jsonl"

timeout 15 adb logcat -d --pid="$PID" > "$OUT/app-logcat.txt"
if grep -E 'FATAL EXCEPTION|Fatal signal|Unhandled Exception|EXCEPTION CAUGHT BY' "$OUT/app-logcat.txt"; then
  echo 'App exception detected' >&2
  exit 1
fi
printf '%s\n' 'PASS: exact APK clean-install location request passed; diagnostic started in Nearby and survived Outing stop; explicit Outing promoted to FGS; process/owner survived verified screen-off; GPS fixes and local trail grew while screen was off; resumed without detected app exception.' > "$OUT/result.txt"
printf '%s\n' 'NOT TESTED: real BLE peer-to-peer, real GNSS error, OEM energy policies, battery endurance, real multi-device HISTORY ACK loss/retry.' >> "$OUT/result.txt"
