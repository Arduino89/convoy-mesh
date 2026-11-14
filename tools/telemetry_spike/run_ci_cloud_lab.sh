#!/usr/bin/env bash
# Called only after the same-source local Android suite has succeeded.
set -euo pipefail
: "${ANDROID_HOME:?Android SDK required}"
: "${JAVA_HOME:?JDK required}"
: "${RUNNER_TEMP:?Disposable runner required}"
: "${GITHUB_WORKFLOW:?Workflow identity required}"
: "${GITHUB_RUN_NUMBER:?Run number required}"
: "${GITHUB_RUN_ATTEMPT:?Run attempt required}"
test "${CONVOY_CLOUD_ENABLED:-false}" = true
test "$GITHUB_RUN_ATTEMPT" = 1
LAB_SOURCE_COMMIT="$(git rev-parse HEAD)"
LAB_CLOUD_RUN_ID="$(python3 -c 'import json, os; print(json.load(open(os.path.join(os.environ["RUNNER_TEMP"], "cloud-private", "gate.json")))["run_id"])')"

# A fresh LAB install starts a distinct cloud experiment. Never clear app data
# between its normal/revocation/retry phases. The local receipts already exist.
"$ANDROID_HOME/platform-tools/adb" -s emulator-5554 uninstall com.cama.telemetry.direct_lab >/dev/null
python3 tools/telemetry_spike/ci_cloud_trial.py \
  --sdk "$ANDROID_HOME" --jdk "$JAVA_HOME" \
  --apk "$RUNNER_TEMP/direct-build/direct-lab.apk" \
  --build-receipt "$RUNNER_TEMP/direct-build/build-receipt.json" \
  --runtime-gate "$RUNNER_TEMP/runtime-control-smoke/receipt.json" \
  --cloud-gate "$RUNNER_TEMP/cloud-private/gate.json" \
  --private-config "$RUNNER_TEMP/cloud-private/config.json" \
  --source-commit "$LAB_SOURCE_COMMIT" --run-id "$LAB_CLOUD_RUN_ID" \
  --execution-id "$GITHUB_WORKFLOW:$GITHUB_RUN_NUMBER" --run-attempt "$GITHUB_RUN_ATTEMPT" \
  --serial emulator-5554 --out "$RUNNER_TEMP/cloud-public"
