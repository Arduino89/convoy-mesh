#!/usr/bin/env bash
# The emulator action starts each script line through sh; enter Bash explicitly.
set -euo pipefail
: "${ANDROID_HOME:?Android SDK required}"
: "${JAVA_HOME:?JDK required}"
: "${RUNNER_TEMP:?Disposable runner required}"
: "${GITHUB_SHA:?Exact diagnostic source required}"

python3 pinned-app/tools/telemetry_spike/runtime_control/smoke.py \
  --sdk "$ANDROID_HOME" --jdk "$JAVA_HOME" \
  --apk "$RUNNER_TEMP/runtime-control-build/runtime-control.apk" \
  --build-receipt "$RUNNER_TEMP/runtime-control-build/build-receipt.json" \
  --serial emulator-5554 --out "$RUNNER_TEMP/runtime-control-smoke" --timeout 60

# Failed control terminates before LAB build or installation/provisioning.
python3 pinned-app/tools/telemetry_spike/direct_trial/build.py \
  --sdk "$ANDROID_HOME" --jdk "$JAVA_HOME" \
  --out "$RUNNER_TEMP/direct-build" \
  --source-commit 2d76100fda1df0637e953f4ad90f26073028880c

python3 tools/telemetry_spike/ci_provision_probe.py \
  --sdk "$ANDROID_HOME" --jdk "$JAVA_HOME" \
  --apk "$RUNNER_TEMP/direct-build/direct-lab.apk" \
  --build-receipt "$RUNNER_TEMP/direct-build/build-receipt.json" \
  --runtime-gate "$RUNNER_TEMP/runtime-control-smoke/receipt.json" \
  --serial emulator-5554 --source-commit "$GITHUB_SHA" \
  --apk-source-commit 2d76100fda1df0637e953f4ad90f26073028880c \
  --out "$RUNNER_TEMP/provision-diagnostic"
