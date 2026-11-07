#!/usr/bin/env python3
"""Statically review the single-use branch wrapper; never dispatch or ingest.

Only four fields may differ from the pinned restored workflow. This verifies
their actual bytes and gate, not GitHub Actions expression execution.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re

from ci_cloud_trial import TrialBlocked, validate_cloud_gate

ORIGINAL_SHA256 = "5e66eb7f83814e4a6bc15accfbc5a5b7f13b4c8e4fc683a83d33d52bff813cc5"
WORKFLOW = "Isolated Android telemetry laboratory"
BRANCH = "experiment/telemetry-runtime-lab"
MARKER = "Execute authorized synthetic cloud laboratory once (additional budget 200)"


def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()


def expected_wrapper(original, source, gate, number):
    if digest(original) != ORIGINAL_SHA256:
        raise TrialBlocked("RESTORED_WORKFLOW_BYTES_NOT_PINNED")
    if not re.fullmatch(r"[a-f0-9]{40}", source) or type(number) is not int or number <= 0:
        raise TrialBlocked("WRAPPER_SOURCE_OR_RUN_INVALID")
    gate_text = json.dumps(gate, separators=(",", ":"), ensure_ascii=True, allow_nan=False)
    if "${{" in gate_text:
        raise TrialBlocked("GATE_MUST_NOT_CONTAIN_ACTIONS_EXPRESSIONS")
    guard = ("github.repository == 'Arduino89/convoy-mesh' && github.event.repository.private == false && "
             "github.event_name == 'push' && github.ref == 'refs/heads/" + BRANCH + "' && "
             "github.run_number == " + str(number) + " && github.run_attempt == 1 && "
             "github.event.head_commit.message == '" + MARKER + "'")
    substitutions = (
        ("    if: github.repository == 'Arduino89/convoy-mesh' && github.event.repository.private == false",
         "    if: " + guard),
        ("      CONVOY_CLOUD_ENABLED: ${{ github.event_name == 'workflow_dispatch' && inputs.cloud_gate_json != '' && inputs.cloud_gate_json != '{}' }}",
         '      CONVOY_CLOUD_ENABLED: "true"'),
        ("          ref: ${{ inputs.source_commit || github.sha }}", "          ref: " + source),
        ("          CONVOY_CLOUD_GATE: ${{ inputs.cloud_gate_json }}",
         "          CONVOY_CLOUD_GATE: '" + gate_text.replace("'", "''") + "'"),
    )
    wrapper = original
    for before, after in substitutions:
        if wrapper.count(before) != 1:
            raise TrialBlocked("EXPECTED_WORKFLOW_FIELD_NOT_UNIQUE")
        wrapper = wrapper.replace(before, after, 1)
    return wrapper


def review_wrapper(original, wrapper, source, gate, number, clock=None):
    clock = clock or datetime.now(timezone.utc)
    if wrapper != expected_wrapper(original, source, gate, number):
        raise TrialBlocked("WRAPPER_HAS_UNREVIEWED_FIELDS_OR_GUARDS")
    remaining = validate_cloud_gate(gate, source, gate.get("run_id"), WORKFLOW + ":" + str(number), 1, clock)
    if (gate.get("schema_version") != 2 or remaining != 200 or gate.get("total_ceiling") != 700 or
            gate.get("prior_rows_conservative_consumed") != 500 or gate.get("additional_rows_authorized") != 200):
        raise TrialBlocked("WRAPPER_NOT_THE_AUTHORIZED_ADDITIONAL_ALLOWANCE")
    allowed = dict(repository="Arduino89/convoy-mesh", private=False, event="push",
                   ref="refs/heads/" + BRANCH, number=number, attempt=1, message=MARKER)
    cases = [("authorized_push", allowed)]
    changes = {"other_repository": {"repository": "other/repo"}, "private_repository": {"private": True},
               "manual_dispatch": {"event": "workflow_dispatch"}, "other_branch": {"ref": "refs/heads/main"},
               "tag_ref": {"ref": "refs/tags/test"}, "previous_run": {"number": number - 1},
               "next_run": {"number": number + 1}, "rerun_attempt_2": {"attempt": 2},
               "wrong_message": {"message": MARKER + " extra"}, "newline_message": {"message": MARKER + "\n"}}
    cases.extend((name, dict(allowed, **changeset)) for name, changeset in changes.items())
    matrix = [{"case": name, "job_enabled": value == allowed} for name, value in cases]
    return {"schema_version": 1, "status": "APPROVED_FOR_SINGLE_LAUNCH",
            "scope": "INDEPENDENT_STATIC_WORKFLOW_AND_GATE_REVIEW_ONLY",
            "checked_at_utc": clock.isoformat(), "source_commit": source,
            "workflow_sha256": digest(wrapper), "restored_workflow_sha256": digest(original),
            "gate_json_sha256": digest(json.dumps(gate, separators=(",", ":"), ensure_ascii=True, allow_nan=False)),
            "expected_run_number": number, "expected_attempt": 1, "expected_branch": BRANCH,
            "expected_commit_message": MARKER, "run_id": gate["run_id"],
            "new_allowance_rows_including_retries": remaining, "historical_conservative_consumption": 500,
            "cumulative_ceiling": 700, "nominal_rows_reserved": 130, "nominal_unique_received": 120,
            "guard_matrix": matrix, "cloud_executed": False, "android_executed": False,
            "limitations": ["Static expression truth table is not a GitHub Actions execution.",
                "Live account controls and local Android receipts are reviewed references, not executed by this verifier.",
                "Exact wrapper commit must be recorded before push; no self-referential commit guard is claimed.",
                "A consumed run number or any failed attempt blocks; no automatic rerun, substitution or refund.",
                "Transport acknowledgment requires separate raw cloud reconciliation; no deletion authorized.",
                "Restore the pinned original workflow using skip-ci after this one execution."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("original", "workflow", "gate", "out"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--number", type=int, required=True)
    args = parser.parse_args()
    result = review_wrapper(args.original.read_text(), args.workflow.read_text(), args.source,
                            json.loads(args.gate.read_text()), args.number)
    args.out.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"status": result["status"], "workflow_sha256": result["workflow_sha256"],
                      "source_commit": args.source, "expected_run_number": args.number}))


if __name__ == "__main__":
    main()
