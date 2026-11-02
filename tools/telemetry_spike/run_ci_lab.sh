#!/usr/bin/env bash
# Run only on the dedicated synthetic emulator created by the GitHub workflow.
set -euo pipefail
: "${ANDROID_HOME:?Android SDK required}"
: "${JAVA_HOME:?JDK required}"
: "${RUNNER_TEMP:?Disposable runner required}"
: "${GITHUB_SHA:?Exact source required}"
: "${LAB_RUN_ID:?Synthetic run required}"
: "${LAB_OVERFLOW_RUN_ID:?Distinct synthetic overflow run required}"

python3 tools/telemetry_spike/runtime_control/smoke.py \
  --sdk "$ANDROID_HOME" --jdk "$JAVA_HOME" \
  --apk "$RUNNER_TEMP/runtime-control-build/runtime-control.apk" \
  --build-receipt "$RUNNER_TEMP/runtime-control-build/build-receipt.json" \
  --serial emulator-5554 --out "$RUNNER_TEMP/runtime-control-smoke" --timeout 60

# A failed independent control terminates this script before SDK build or calls.
python3 tools/telemetry_spike/ci_build_trial.py \
  --out "$RUNNER_TEMP/lab-build" --source-commit "$GITHUB_SHA" \
  --run-id "$LAB_RUN_ID" --overflow-run-id "$LAB_OVERFLOW_RUN_ID"

normal_sha=$(sha256sum "$RUNNER_TEMP/lab-build/normal.apk" | cut -d ' ' -f 1)
overflow_sha=$(sha256sum "$RUNNER_TEMP/lab-build/overflow.apk" | cut -d ' ' -f 1)
python3 tools/telemetry_spike/ci_native_trial.py \
  --normal-apk "$RUNNER_TEMP/lab-build/normal.apk" --normal-sha256 "$normal_sha" \
  --overflow-apk "$RUNNER_TEMP/lab-build/overflow.apk" --overflow-sha256 "$overflow_sha" \
  --runtime-gate "$RUNNER_TEMP/runtime-control-smoke/receipt.json" \
  --run-id "$LAB_RUN_ID" --overflow-run-id "$LAB_OVERFLOW_RUN_ID" \
  --aapt2 "$ANDROID_HOME/build-tools/36.0.0/aapt2" \
  --apksigner "$ANDROID_HOME/build-tools/36.0.0/apksigner" \
  --source-commit "$GITHUB_SHA" --serial emulator-5554 --out "$RUNNER_TEMP/lab-public"
