#!/usr/bin/env bash
set -euo pipefail
base=${1:?signed +22 path required}
candidate=${2:?signed +23 path required}
PACKAGE=com.example.convoy_mesh.outdoor
mkdir -p evidence
collect() {
  adb logcat -d > evidence/logcat.txt 2>&1 || true
  adb shell dumpsys package "$PACKAGE" > evidence/package-final.txt 2>&1 || true
  adb shell dumpsys activity activities > evidence/activity-final.txt 2>&1 || true
}
trap collect EXIT
assert_version() {
  adb shell dumpsys package "$PACKAGE" > "evidence/package-$1.txt"
  grep -Fq "versionCode=$1 " "evidence/package-$1.txt"
}
adb install "$base" | tee evidence/install-22.txt
grep -Fq Success evidence/install-22.txt
assert_version 22
for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_SCAN BLUETOOTH_CONNECT BLUETOOTH_ADVERTISE POST_NOTIFICATIONS; do
  adb shell pm grant "$PACKAGE" "android.permission.$p"
done
# Deliberately seed private synthetic preferences: the previous cold-start
# +19 identity-bootstrap test timed out. This tests Android's in-place
# persistence, NOT the cold-start identity contract; keep that HOLD.
cat > evidence/prefs-before.xml <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<map>
  <long name="flutter.my_id" value="4242" />
  <string name="flutter.my_name">SyntheticWiFiUpgrade</string>
</map>
XML
printf 'CONVOY_SYNTHETIC_UPGRADE_MARKER\n' > evidence/marker-before.txt
adb shell "run-as $PACKAGE mkdir -p shared_prefs files/convoy-diagnostics"
adb shell "run-as $PACKAGE sh -c 'cat > shared_prefs/FlutterSharedPreferences.xml'" < evidence/prefs-before.xml
adb shell "run-as $PACKAGE sh -c 'cat > files/convoy-diagnostics/upgrade-proof.txt'" < evidence/marker-before.txt
adb exec-out run-as "$PACKAGE" cat shared_prefs/FlutterSharedPreferences.xml > evidence/prefs-22.xml
adb exec-out run-as "$PACKAGE" cat files/convoy-diagnostics/upgrade-proof.txt > evidence/marker-22.txt
cmp evidence/prefs-before.xml evidence/prefs-22.xml
cmp evidence/marker-before.txt evidence/marker-22.txt
assert_version 22
adb install -r "$candidate" | tee evidence/install-23.txt
grep -Fq Success evidence/install-23.txt
assert_version 23
adb exec-out run-as "$PACKAGE" cat shared_prefs/FlutterSharedPreferences.xml > evidence/prefs-23.xml
adb exec-out run-as "$PACKAGE" cat files/convoy-diagnostics/upgrade-proof.txt > evidence/marker-23.txt
cmp evidence/prefs-22.xml evidence/prefs-23.xml
cmp evidence/marker-22.txt evidence/marker-23.txt
for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_SCAN BLUETOOTH_CONNECT BLUETOOTH_ADVERTISE POST_NOTIFICATIONS; do
  grep -Fq "android.permission.$p: granted=true" evidence/package-22.txt
  grep -Fq "android.permission.$p: granted=true" evidence/package-23.txt
done
adb shell am start -n "$PACKAGE/com.example.convoy_mesh.MainActivity" | tee evidence/launch-23.txt
for i in $(seq 1 30); do
  if adb shell pidof "$PACKAGE" | grep -q '[0-9]'; then break; fi
  sleep 2
done
adb shell pidof "$PACKAGE" | grep -q '[0-9]'
sleep 5
adb shell pidof "$PACKAGE" | grep -q '[0-9]'
if adb install -r "$base" > evidence/downgrade.txt 2>&1; then
  echo "::error::Downgrade incorrectly accepted"; exit 1
fi
grep -Fq INSTALL_FAILED_VERSION_DOWNGRADE evidence/downgrade.txt
echo 'PASS: actual signed +22 to signed +23 in-place, synthetic preferences/diagnostics and permissions preserved, +23 launches, downgrade rejected. Cold-install initialization NOT tested.' | tee evidence/result.txt
