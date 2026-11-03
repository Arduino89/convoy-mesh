#!/usr/bin/env python3
"""Create mode0600 gated cloud inputs from step-scoped environment, without ADB.

CONVOY_CLOUD_GATE is a verified JSON gate for the actual checked-out commit and
GITHUB_WORKFLOW:GITHUB_RUN_NUMBER. CONVOY_LAB_POSTHOG_TOKEN never enters argv,
source, stdout or public evidence. A pending gate creates no credential file.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

from ci_cloud_trial import ENDPOINT, TrialBlocked, validate_cloud_gate

REPO = Path(__file__).resolve().parents[2]


def prepare(out, environment, source, clock=None):
    try:
        gate = json.loads(environment.get("CONVOY_CLOUD_GATE", ""))
        execution = environment["GITHUB_WORKFLOW"] + ":" + environment["GITHUB_RUN_NUMBER"]
        attempt = int(environment["GITHUB_RUN_ATTEMPT"])
        run_id = gate["run_id"]
    except (ValueError, KeyError, TypeError) as exc:
        raise TrialBlocked("CLOUD_EXECUTION_ENVIRONMENT_OR_GATE_MISSING") from exc
    remaining = validate_cloud_gate(gate, source, run_id, execution, attempt, clock)
    secret = environment.get("CONVOY_LAB_POSTHOG_TOKEN", "")
    if not re.fullmatch(r"phc_[A-Za-z0-9_-]{16,200}", secret) or secret == "phc_synthetic_local_only":
        raise TrialBlocked("CLOUD_INGESTION_SECRET_UNAVAILABLE")
    out.mkdir(mode=0o700, parents=True, exist_ok=False)
    config = {"mode": "posthog_cloud", "endpoint": ENDPOINT, "api_key": secret,
              "run_id": run_id, "row_limit": remaining}
    for name, value in (("gate.json", gate), ("config.json", config)):
        descriptor = os.open(out / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as output:
            json.dump(value, output, separators=(",", ":"))
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
    return {"status": "PREPARED_PRIVATE_CLOUD_INPUTS", "source_commit": source,
            "run_id": run_id, "execution_id": execution, "run_attempt": attempt,
            "remaining_budget": remaining}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, help="defaults to RUNNER_TEMP/cloud-private")
    args = parser.parse_args()
    try:
        commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=REPO, capture_output=True,
                                text=True, timeout=10, check=True).stdout.strip()
        out = args.out or Path(os.environ["RUNNER_TEMP"]) / "cloud-private"
        result = prepare(out, os.environ, commit)
    except (TrialBlocked, OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError) as exc:
        print(json.dumps({"status": "BLOCKED", "reason": str(exc) if isinstance(exc, TrialBlocked)
                          else "CLOUD_PRIVATE_INPUT_PREPARATION_FAILED"}))
        return 1
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
