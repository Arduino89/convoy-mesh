#!/usr/bin/env bash
# Run only on the dedicated synthetic emulator created by the GitHub workflow.
set -euo pipefail
: "${ANDROID_HOME:?Android SDK required}"
: "${JAVA_HOME:?JDK required}"
: "${RUNNER_TEMP:?Disposable runner required}"
: "${GITHUB_SHA:?Exact source required}"
: "${LAB_RUN_ID:?Synthetic run required}"

python3 tools/telemetry_spike/runtime_control/smoke.py \
  --sdk "$ANDROID_HOME" --jdk "$JAVA_HOME" \
  --apk "$RUNNER_TEMP/runtime-control-build/runtime-control.apk" \
  --build-receipt "$RUNNER_TEMP/runtime-control-build/build-receipt.json" \
  --serial emulator-5554 --out "$RUNNER_TEMP/runtime-control-smoke" --timeout 60

# A failed independent control terminates this script before LAB build or calls.
# The historical SDK sources/receipts remain unchanged; this candidate uses no SDK.
python3 tools/telemetry_spike/direct_trial/build.py \
  --sdk "$ANDROID_HOME" --jdk "$JAVA_HOME" \
  --out "$RUNNER_TEMP/direct-build" --source-commit "$GITHUB_SHA"

python3 tools/telemetry_spike/ci_direct_trial.py \
  --sdk "$ANDROID_HOME" --jdk "$JAVA_HOME" \
  --apk "$RUNNER_TEMP/direct-build/direct-lab.apk" \
  --build-receipt "$RUNNER_TEMP/direct-build/build-receipt.json" \
  --runtime-gate "$RUNNER_TEMP/runtime-control-smoke/receipt.json" \
  --run-id "$LAB_RUN_ID" --source-commit "$GITHUB_SHA" \
  --serial emulator-5554 --out "$RUNNER_TEMP/direct-public"
