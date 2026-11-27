#!/usr/bin/env bash
set -Eeuo pipefail
APK=${1:?APK path required}
PACKAGE=${2:-com.example.convoy_mesh}
ACTIVITY=com.example.convoy_mesh.MainActivity
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
trap 'printf "Smoke failed at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2; tail -15 "$OUT/readiness.txt" >&2 || true' ERR
runtime_ready() {
  local name=$1
  timeout 15 adb shell dumpsys activity services "$PACKAGE" > "$OUT/services-$name.txt" || return 1
  awk -v package="$PACKAGE" '
    /\* ServiceRecord\{/ { own = index($0, package "/") && /ConvoyForegroundService/ }
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
  timeout 30 adb shell am start -n "$PACKAGE/$ACTIVITY" | tee "$OUT/launch-$name.txt"
  if grep -E 'Error:|Exception' "$OUT/launch-$name.txt"; then return 1; fi
  wait_for_process "$name"
}
launch_app_runtime() {
  local name=$1
  timeout 30 adb shell am start -n "$PACKAGE/$ACTIVITY" | tee "$OUT/launch-$name.txt"
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
if [[ "$PACKAGE" == "com.example.convoy_mesh.wifilab" ]]; then
  timeout 15 adb shell pm grant "$PACKAGE" android.permission.NEARBY_WIFI_DEVICES >/dev/null 2>&1 || true
  for permission in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_SCAN BLUETOOTH_CONNECT BLUETOOTH_ADVERTISE; do
    timeout 15 adb shell pm revoke "$PACKAGE" "android.permission.$permission" >/dev/null 2>&1 || true
  done
  timeout 15 adb shell cmd bluetooth_manager disable >/dev/null 2>&1 || true
  timeout 15 adb shell input keyevent KEYCODE_WAKEUP
  timeout 15 adb shell wm dismiss-keyguard
  timeout 15 adb logcat -c

  launch_app_process wifilab-first-run
  sleep 4
  assert_no_runtime wifilab-boot
  timeout 15 adb exec-out screencap -p > "$OUT/wifilab-screen.png"
  timeout 15 adb shell uiautomator dump /sdcard/convoy-wifilab-ui.xml >/dev/null 2>&1 || true
  timeout 15 adb shell cat /sdcard/convoy-wifilab-ui.xml > "$OUT/ui-wifilab.xml" 2>/dev/null || true
  grep -Fq 'Convoy Wi-Fi Direct LAB' "$OUT/ui-wifilab.xml"
  if grep -Eq 'Radar BLE|Avvia uscita' "$OUT/ui-wifilab.xml"; then
    echo 'Wi-Fi Direct LAB unexpectedly mounted AppShell/BLE UI' >&2
    exit 1
  fi
  timeout 15 adb shell dumpsys package "$PACKAGE" > "$OUT/wifilab-permissions.txt"
  if grep -Eq 'android\.permission\.ACCESS_(FINE|COARSE)_LOCATION: granted=true' "$OUT/wifilab-permissions.txt"; then
    echo 'Wi-Fi Direct LAB unexpectedly requested or received location permission on API 35' >&2
    exit 1
  fi
  timeout 15 adb logcat -d --pid="$PID" > "$OUT/app-logcat.txt"
  if grep -E 'FATAL EXCEPTION|Fatal signal|Unhandled Exception|EXCEPTION CAUGHT BY' "$OUT/app-logcat.txt"; then
    echo 'App exception detected in Wi-Fi Direct LAB' >&2
    exit 1
  fi
  printf '%s\n' 'PASS: Wi-Fi Direct Offline Lab APK installed as com.example.convoy_mesh.wifilab; launched isolated WifiDirectOfflineLabApp with Bluetooth off, zero location permission granted on API 35, zero ConvoyForegroundService runtime, zero AppShell/BLE startup, and zero app exceptions.' > "$OUT/result.txt"
  printf '%s\n' 'NOT TESTED: physical two-phone Wi-Fi Direct radio discovery, group formation, range (10..150 m), OEM P2P behavior, and screen-off battery impact require two real Android handsets.' >> "$OUT/result.txt"
  exit 0
fi
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
timeout 15 adb shell dumpsys package "$PACKAGE" > "$OUT/location-permission.txt"
grep -Eq 'android\.permission\.ACCESS_(FINE|COARSE)_LOCATION: granted=true' "$OUT/location-permission.txt"
assert_no_runtime nearby
timeout 15 adb exec-out screencap -p > "$OUT/nearby-screen.png"

# A diagnostic session may begin BEFORE an outing and must span the transition.
wait_and_tap_text 'Test log' open-test-log
# The integrated branch uses the same Outdoor package; the Wi-Fi LAB is a
# separate route, not a second installed app or an always-running transport.
if [[ "$PACKAGE" == "com.example.convoy_mesh.outdoor" && "${EXPECTED_OUTDOOR_VERSION:-}" == "0.7.7-outdoor+27" ]]; then
  timeout 15 adb shell cmd location set-location-enabled false
  wait_and_tap_text 'Apri Wi-Fi Direct LAB (solo probe sintetici)' open-integrated-wifi
  sleep 3
  assert_no_runtime wifi-lab-open
  for try in {1..5}; do
    if timeout 15 adb shell uiautomator dump /sdcard/convoy-integrated-lab.xml >/dev/null &&
      timeout 15 adb shell cat /sdcard/convoy-integrated-lab.xml > "$OUT/ui-integrated-wifi.xml" &&
      grep -Fq 'Convoy Wi-Fi Direct LAB' "$OUT/ui-integrated-wifi.xml"; then
      break
    fi
    sleep 1
  done
  grep -Fq 'Convoy Wi-Fi Direct LAB' "$OUT/ui-integrated-wifi.xml"
  if grep -Fq 'Torna a Convoy mantenendo il gruppo' "$OUT/ui-integrated-wifi.xml"; then
    echo 'Retention offered without a Wi-Fi Direct group' >&2
    exit 1
  fi
  read -r width height < <(timeout 15 adb shell wm size | tr -d '\r' |
    awk -F '[: x]+' '/ size:/ {width=$(NF-1); height=$NF} END {print width, height}')
  location_ui=$OUT/ui-wifi-lab-location-off.xml
  for try in {1..5}; do
    if timeout 15 adb shell uiautomator dump /sdcard/convoy-lab-location.xml >/dev/null &&
      timeout 15 adb shell cat /sdcard/convoy-lab-location.xml > "$location_ui"; then
      if grep -Fq 'Impostazioni Posizione' "$location_ui"; then break; fi
      timeout 15 adb shell input swipe "$((width / 2))" "$((height * 68 / 100))" \
        "$((width / 2))" "$((height * 40 / 100))" 500
    fi
  done
  grep -Fq 'Impostazioni Posizione' "$location_ui"
  timeout 15 adb shell cmd location set-location-enabled true
  echo "PASS: LAB explains disabled Android Location Mode with a settings action on API 35"
  timeout 15 adb shell input keyevent KEYCODE_HOME
  sleep 2
  assert_no_runtime wifi-lab-background
  timeout 15 adb shell dumpsys activity services "$PACKAGE" > "$OUT/wifi-lab-services.txt"
  if grep -Fq 'WifiDirectLabService' "$OUT/wifi-lab-services.txt"; then
    echo 'Wi-Fi Direct background service started without explicit consent' >&2
    exit 1
  fi
  launch_app_process wifi-lab-resumed
  assert_no_runtime wifi-lab-resumed
  wait_and_tap_text 'Chiudi LAB e torna a Convoy' return-integrated-outdoor
  sleep 3
  assert_no_runtime wifi-lab-return
  timeout 15 adb shell uiautomator dump /sdcard/convoy-return-outdoor.xml >/dev/null 2>&1 || true
  timeout 15 adb shell cat /sdcard/convoy-return-outdoor.xml > "$OUT/ui-return-outdoor.xml"
  grep -Fq 'Test diagnostico' "$OUT/ui-return-outdoor.xml"
  echo "PASS: LAB returned through Android Home/resume and closed without foreground runtime"
fi
# The start control is deliberately before the explanatory text. Do NOT
# swipe here: a previous unconditional swipe hid the button above the
# viewport in actual emulator UI dumps. Capture the pre-tap view to
# diagnose any future Android UI/permission issues without guessing.
timeout 15 adb exec-out screencap -p > "$OUT/diagnostic-before-start.png"
wait_and_tap_text 'Avvia registrazione diagnostica • max 4 min' start-diagnostic
sleep 2
capture_diag nearby-test
grep -q '"category":"session","event":"start"' "$OUT/diag-nearby-test.jsonl"
if grep -q '"category":"session","event":"stop"' "$OUT/diag-nearby-test.jsonl"; then
  echo 'Diagnostic session stopped unexpectedly in Nearby mode' >&2
  exit 1
fi

# Exercise the real preview path before the outing takes ownership of the trail.
# These are synthetic emulator coordinates, never a person's field recording.
wait_and_tap_text 'Mappa' open-map
wait_and_tap_text 'Posizione non agganciata • tocca per localizzarti' start-preview
for i in 1 2 3 4; do
  timeout 10 adb emu geo fix 10.0 45.0 >> "$OUT/gps-injection.txt" 2>&1
  sleep 5
done
assert_no_runtime preview
capture_diag preview
python3 - "$OUT/diag-preview.jsonl" "${EXPECTED_BUILD_COMMIT:-}" "$PACKAGE" "${EXPECTED_OUTDOOR_VERSION:-}" <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
start = next(r['data'] for r in rows if r['category'] == 'session' and r['event'] == 'start')
if sys.argv[2]:
    assert start['build_commit'] == sys.argv[2], start
expected_version = {
    'com.example.convoy_mesh.outdoor': sys.argv[4],
    'com.example.convoy_mesh.diaglab': '0.7.7-diaglab+15',
}.get(sys.argv[3], '0.7.7-exp1+9')
assert expected_version, 'Outdoor expected version must be supplied by CI'
assert start['app_version'] == expected_version, start
fixes = [r['data'] for r in rows if r['category'] == 'gps' and r['event'] == 'fix']
assert fixes and any(f['fresh'] for f in fixes), 'Preview did not acquire a real provider fix'
assert all(not f['record_track'] and not f['track_added'] and f['track_points_total'] == 0 for f in fixes)
snapshots = [r['data'] for r in rows if r['category'] == 'runtime' and r['event'] == 'snapshot']
assert all(not s['outing_active'] and not s['foreground_service'] and s['local_trail_points'] == 0 for s in snapshots)
PY

# Explicitly start an outing through the real UI. Only now must FGS appear.
wait_and_tap_text 'Avvia uscita' start-outing
wait_for_runtime outing
assert_runtime outing
timeout 15 adb exec-out screencap -p > "$OUT/outing-screen.png"

# Give the estimator a stationary acquisition cluster, then prove that the
# trajectory records a trail while the screen is still on. This is the control
# for the same continuous GPS-only walk below, not a slow-walking/IMU test.
for i in 1 2 3; do
  timeout 10 adb emu geo fix 10.0 45.0 >> "$OUT/gps-injection.txt" 2>&1
  sleep 5
done
for i in $(seq 1 6); do
  latitude=$(python3 -c "print(45.0 + $i * 0.00006)")
  timeout 10 adb emu geo fix 10.0 "$latitude" >> "$OUT/gps-injection.txt" 2>&1
  sleep 5
done
capture_diag before-screen-off
if [[ "$PACKAGE" == 'com.example.convoy_mesh.outdoor' ]]; then
  python3 - "$OUT/diag-before-screen-off.jsonl" <<'PY'
import json, sys
from datetime import datetime
rows = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
promotions = [r for r in rows if r['category']=='gps' and r['event']=='mode_transition']
assert len(promotions) == 1, 'Expected one warm preview promotion'
promotion = promotions[0]
p = promotion['data']
assert p['reason'] == 'preview_to_outing' and p['record_track'], p
assert p['fresh'] and p['gps_ready'], 'The steady emulator preview should still be ready at promotion'
requests = [r for r in rows if r['category']=='gps' and r['event']=='position_request']
assert len(requests) == 1 and requests[0]['event_index'] < promotion['event_index'], 'GPS provider restarted during warm handoff'
boundary = datetime.fromisoformat(p['outing_started_utc'].replace('Z', '+00:00'))
for r in rows:
    if r['category'] == 'gps' and r['event'] == 'fix' and r['data']['track_added']:
        assert r['event_index'] > promotion['event_index']
        for k in ['source_ts_utc', 'coordinate_ts_utc', 'supported_ts_utc']:
            assert datetime.fromisoformat(r['data'][k].replace('Z', '+00:00')) > boundary, (k, r['event_index'])
print('PASS: warm preview promoted with fresh source fix, one provider request, no pre-outing track points')
PY
fi
BASE_FIXES=$(count_matches '"category":"gps","event":"fix"' "$OUT/diag-before-screen-off.jsonl")
BASE_TRACK=$(count_matches '"track_added":true' "$OUT/diag-before-screen-off.jsonl")
if [ "$BASE_TRACK" -eq 0 ]; then
  echo 'Control trajectory produced no trail before screen-off' >&2
  exit 1
fi
printf '%s\n' "SCREEN_ON_CONTROL: gps_fix=$BASE_FIXES track_added=$BASE_TRACK; injected step=0.00006 latitude degrees/5s (~1.33m/s), IMU motion not simulated" >> "$OUT/readiness.txt"

timeout 15 adb shell input keyevent KEYCODE_HOME
timeout 15 adb shell input keyevent KEYCODE_SLEEP
sleep 2
timeout 15 adb shell dumpsys power > "$OUT/power-screen-off.txt"
grep -Eq 'mWakefulness=(Asleep|Dozing)' "$OUT/power-screen-off.txt"
# Establish the log boundary only AFTER Android reports sleep. Transition
# records from HOME/SLEEP cannot count as successful screen-off evidence.
capture_diag screen-off-start
OFF_BASE_LINES=$(wc -l < "$OUT/diag-screen-off-start.jsonl")
OFF_BASE_FIXES=$(count_matches '"category":"gps","event":"fix"' "$OUT/diag-screen-off-start.jsonl")
OFF_BASE_TRACK=$(count_matches '"track_added":true' "$OUT/diag-screen-off-start.jsonl")

# Continue the SAME ordinary walk (~6.7 m / 5 s) while the screen is off.
# The previous ~0.44 m/s stimulus advanced only ~8.9 m in the 20 s GPS evidence
# window, below its 10 m gate, while emulator IMU remained still. It also failed
# without screen-off; preserve that measured limitation, not a lifecycle claim.
# This proves more than process survival: GPS fixes must continue and the local
# filtered trail must gain fresh points from the post-screen-off tail.
for i in $(seq 7 20); do
  latitude=$(python3 -c "print(45.0 + $i * 0.00006)")
  timeout 10 adb emu geo fix 10.0 "$latitude" >> "$OUT/gps-injection.txt" 2>&1
  sleep 5
done
assert_runtime screen-off
timeout 15 adb shell dumpsys power > "$OUT/power-screen-off-end.txt"
grep -Eq 'mWakefulness=(Asleep|Dozing)' "$OUT/power-screen-off-end.txt"
sleep 2
capture_diag screen-off
tail -n +$((OFF_BASE_LINES + 1)) "$OUT/diag-screen-off.jsonl" > "$OUT/diag-screen-off-tail.jsonl"
AFTER_FIXES=$(count_matches '"category":"gps","event":"fix"' "$OUT/diag-screen-off.jsonl")
AFTER_TRACK=$(count_matches '"track_added":true' "$OUT/diag-screen-off.jsonl")
if [ "$AFTER_FIXES" -le "$OFF_BASE_FIXES" ]; then
  echo "No new GPS fixes while screen was off ($OFF_BASE_FIXES -> $AFTER_FIXES)" >&2
  exit 1
fi
if [ "$AFTER_TRACK" -le "$OFF_BASE_TRACK" ]; then
  echo "Local trail did not grow while screen was off ($OFF_BASE_TRACK -> $AFTER_TRACK)" >&2
  exit 1
fi
python3 - "$OUT/diag-screen-off.jsonl" "$OUT/diag-screen-off-tail.jsonl" <<'PY'
import json, math, sys
from datetime import datetime
rows = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
fixes = [r['data'] for r in rows if r['category'] == 'gps' and r['event'] == 'fix']
outing = [f for f in fixes if f['record_track']]
assert outing and outing[0]['track_points_total'] == 0, 'Preview leaked into outing history'
assert not outing[0]['track_added'], 'First outing observation was prematurely confirmed'
added = [f for f in outing if f['track_added']]
assert added, 'Outing produced no track evidence'
tail = [json.loads(line) for line in open(sys.argv[2]) if line.strip()]
off_fixes = [r['data'] for r in tail if r['category'] == 'gps' and r['event'] == 'fix']
off_added = [f for f in off_fixes if f['track_added']]
assert len(off_fixes) >= 8 and len(off_added) >= 3, 'Insufficient new screen-off GPS/trail evidence'
source_times = [datetime.fromisoformat(f['source_ts_utc'].replace('Z', '+00:00')) for f in off_fixes]
assert all(b > a for a, b in zip(source_times, source_times[1:])), 'Non-increasing source times'
span = (source_times[-1] - source_times[0]).total_seconds()
assert span >= 45, f'Screen-off source evidence too short: {span}s'
def distance(a, b):
    lat1, lat2 = math.radians(a['raw_lat']), math.radians(b['raw_lat'])
    dlat, dlon = lat2 - lat1, math.radians(b['raw_lon'] - a['raw_lon'])
    h = math.sin(dlat / 2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2)**2
    return 6371000 * 2 * math.asin(min(1, math.sqrt(h)))
net = distance(off_fixes[0], off_fixes[-1])
assert net >= 45 and 0.8 <= net / span <= 2.0, f'Wrong delivered walking stimulus: {net}m/{span}s'
for a, b, t0, t1 in zip(off_fixes, off_fixes[1:], source_times, source_times[1:]):
    assert distance(a, b) / (t1 - t0).total_seconds() <= 4.2, 'Injected trajectory contains a jump'
for f in off_added:
    assert f['record_track'], 'Screen-off point was not owned by Outing'
    assert f['fresh'] and f['display_lat'] is not None and f['display_lon'] is not None
    received = datetime.fromisoformat(f['received_ts_utc'].replace('Z', '+00:00'))
    supported = datetime.fromisoformat(f['supported_ts_utc'].replace('Z', '+00:00'))
    assert 0 <= (received - supported).total_seconds() <= 15, f
print(f'SCREEN_OFF_DELIVERED: fixes={len(off_fixes)} new_tracks={len(off_added)} source_span={span:.2f}s net={net:.2f}m speed={net/span:.2f}m/s')
PY
printf '%s\n' "SCREEN_OFF_EVIDENCE: gps_fix=$OFF_BASE_FIXES->$AFTER_FIXES track_added=$OFF_BASE_TRACK->$AFTER_TRACK" >> "$OUT/readiness.txt"

timeout 15 adb shell input keyevent KEYCODE_WAKEUP
timeout 15 adb shell wm dismiss-keyguard
launch_app_runtime resumed
sleep 5
assert_runtime resumed

# Ending the outing must NOT end the diagnostic session.
# Refresh the genuine emulator provider fix just before leaving Outing.
# Otherwise an expired last measurement could mislead this warm-handoff gate.
timeout 10 adb emu geo fix 10.0 45.0012 >> "$OUT/gps-injection.txt" 2>&1
sleep 4
capture_diag before-outing-stop
STOP_BASE_LINES=$(wc -l < "$OUT/diag-before-outing-stop.jsonl")
wait_and_tap_text 'Uscita attiva • Termina uscita' stop-outing
# The foreground map must stay on the SAME GPS stream; request one new real
# emulator callback after the boundary, not a made-up software freshness tick.
timeout 10 adb emu geo fix 10.0 45.0012 >> "$OUT/gps-injection.txt" 2>&1
sleep 5
assert_no_runtime after-outing-stop
capture_diag after-outing-stop
if grep -q '"category":"session","event":"stop"' "$OUT/diag-after-outing-stop.jsonl"; then
  echo 'Diagnostic session was coupled to Termina uscita' >&2
  exit 1
fi
tail -n +$((STOP_BASE_LINES + 1)) "$OUT/diag-after-outing-stop.jsonl" > "$OUT/diag-after-stop-tail.jsonl"
grep -q '"outing_active":false' "$OUT/diag-after-stop-tail.jsonl"
if [[ "$PACKAGE" == 'com.example.convoy_mesh.outdoor' ]]; then
  python3 - "$OUT/diag-before-outing-stop.jsonl" "$OUT/diag-after-outing-stop.jsonl" <<'PY'
import json, sys
before = [json.loads(s) for s in open(sys.argv[1]) if s.strip()]
after = [json.loads(s) for s in open(sys.argv[2]) if s.strip()]
first_stop = max(r['event_index'] for r in before)
tail = [r for r in after if r['event_index'] > first_stop]
handoff = [r for r in tail if r['category'] == 'gps' and r['event'] == 'mode_transition' and r['data'].get('reason') == 'outing_to_preview']
assert len(handoff) == 1, 'WARM_STOP_HANDOFF: expected one visible-map outing->preview transition'
t = handoff[0]
assert t['data']['record_track'] is False and t['data']['fresh'] is True, 'WARM_STOP_FRESH: fresh original source fix must survive stop'
assert not [r for r in tail if r['category']=='gps' and r['event']=='position_request'], 'WARM_STOP_RESTART: GPS provider must not be restarted'
# The pre-tap capture precedes UI lookup and input. The mode transition is
# emitted when the service switches off track recording.
fixes = [r['data'] for r in tail if r['event_index'] > t['event_index'] and r['category']=='gps' and r['event']=='fix']
assert fixes and any(f['fresh'] for f in fixes), 'WARM_STOP_FRESH: new physical provider callback required'
assert all(f['record_track'] is False and f['track_added'] is False for f in fixes), 'WARM_STOP_TRAIL: after-stop fixes must not extend outing'
assert not [r for r in tail if r['category']=='runtime' and r['event']=='foreground_service_started'], 'WARM_STOP_FOREGROUND: stopped outing must not restart FGS'
print('PASS: Map owns foreground GPS preview after outing, no new provider request/FGS/trail')
PY
fi

timeout 15 adb logcat -d --pid="$PID" > "$OUT/app-logcat.txt"
if grep -E 'FATAL EXCEPTION|Fatal signal|Unhandled Exception|EXCEPTION CAUGHT BY' "$OUT/app-logcat.txt"; then
  echo 'App exception detected' >&2
  exit 1
fi
printf '%s\n' 'PASS: exact APK/build stamp and clean-install location request passed; preview acquired without FGS/trail and did not leak into Outing; diagnostic started in Nearby and survived Outing stop; explicit Outing promoted to FGS; foreground Map retains GPS provider without restarting after Outing stop; process/owner survived verified screen-off; fresh GPS fixes and local trail grew while screen was off; resumed without detected app exception.' > "$OUT/result.txt"
printf '%s\n' 'NOT TESTED: very slow walking with quiet/unavailable IMU, real BLE peer-to-peer, real GNSS error, IMU motion, forced Doze, OEM energy policies, battery endurance, real multi-device HISTORY ACK loss/retry; dropout/segment correctness is a separate synthetic unit-test gate.' >> "$OUT/result.txt"
