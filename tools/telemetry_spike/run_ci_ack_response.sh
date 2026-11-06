#!/usr/bin/env bash
# Only permissionless fixtures; no LAB sender, cloud configuration or credential.
set -euo pipefail
: "${ANDROID_HOME:?Android SDK required}"
: "${JAVA_HOME:?JDK required}"
: "${RUNNER_TEMP:?Disposable runner required}"
: "${BASELINE_JAVA:?Pinned baseline source required}"
LAB_SOURCE_COMMIT="$(git rev-parse HEAD)"

python3 tools/telemetry_spike/runtime_control/smoke.py \
  --sdk "$ANDROID_HOME" --jdk "$JAVA_HOME" \
  --apk "$RUNNER_TEMP/runtime-control-build/runtime-control.apk" \
  --build-receipt "$RUNNER_TEMP/runtime-control-build/build-receipt.json" \
  --serial emulator-5554 --out "$RUNNER_TEMP/runtime-control-smoke" --timeout 60

python3 tools/telemetry_spike/ack_response_trial/build.py \
  --sdk "$ANDROID_HOME" --jdk "$JAVA_HOME" --out "$RUNNER_TEMP/ack-proof-build" \
  --baseline-java "$BASELINE_JAVA" --source-commit "$LAB_SOURCE_COMMIT"

python3 tools/telemetry_spike/ci_ack_response_trial.py \
  --sdk "$ANDROID_HOME" --jdk "$JAVA_HOME" --build "$RUNNER_TEMP/ack-proof-build" \
  --runtime-gate "$RUNNER_TEMP/runtime-control-smoke/receipt.json" \
  --control-build "$RUNNER_TEMP/runtime-control-build/build-receipt.json" \
  --serial emulator-5554 --source-commit "$LAB_SOURCE_COMMIT" --out "$RUNNER_TEMP/ack-proof-public"
