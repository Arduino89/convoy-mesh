#!/usr/bin/env python3
"""Reconcile a bounded synthetic PostHog readback without hiding duplicate rows.

This program makes no network requests. Connector output is a private input;
unknown cloud metadata values are never copied to public evidence. HTTP responses
are transport observations, never proof that the cloud stored an event.
"""
import argparse
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import re

from ci_native_trial import TrialBlocked, public_write, validate_public_value
from probe import event, reconcile, validate
from wire_audit_receiver import FIELDS, PROPERTIES, TOKEN, audit_payload, is_uuid, key, shape

PROJECT = 330212
READBACK_COLUMNS = ["uuid", "event", "properties", "timestamp", "distinct_id", "created_at", "person_mode", "person_id"]
READBACK_KEYS = set(READBACK_COLUMNS)
SOURCE_SCOPE = "DIRECT_CLOUD_SYNTHETIC_POSTHOG"
OUTPUT_SCOPE = "DIRECT_CLOUD_RAW_READBACK_NOT_UNIVERSAL_DEDUPLICATION_PROOF"
MAX_INPUT_BYTES = 4 * 1024 * 1024


def expected_queries(transport, preflight):
    """Date-first raw/count queries; same predicate, never query deduplication.

    Five minutes of clock margin plus outward whole-second rounding is explicit.
    Mutations outside this timestamp window are not ruled out by the query.
    """
    run_id = transport_provenance(transport)
    started = datetime.fromisoformat(canonical_time(transport.get("started_utc")))
    finished = datetime.fromisoformat(canonical_time(transport.get("finished_utc")))
    if finished < started:
        raise TrialBlocked("TRANSPORT_TIME_ORDER_INVALID")
    begin = started.replace(microsecond=0) - timedelta(seconds=300)
    end = finished.replace(microsecond=0) + timedelta(seconds=300 + bool(finished.microsecond))
    uuids = set()
    for receipt in preflight:
        payload = receipt.get("payload", {}) if isinstance(receipt, dict) else {}
        if isinstance(payload, dict) and set(payload) == {"batch"}:
            audit = audit_payload(dict(payload, api_key=TOKEN), run_id)
            if not audit["violations"]:
                for item in payload["batch"]:
                    stamp = datetime.fromisoformat(canonical_time(item["timestamp"]))
                    if not begin <= stamp <= end:
                        raise TrialBlocked("CLIENT_TIMESTAMP_OUTSIDE_QUERY_WINDOW")
                    uuids.add(item["uuid"].lower())
    if not uuids:
        raise TrialBlocked("NO_ATTESTED_CLIENT_UUID_FOR_QUERY")
    selector = ("timestamp >= toDateTime('" + begin.strftime("%Y-%m-%d %H:%M:%S") + "', 'UTC') "
                "AND timestamp <= toDateTime('" + end.strftime("%Y-%m-%d %H:%M:%S") + "', 'UTC') "
                "AND (properties.run_id = '" + run_id + "' OR distinct_id = '" + run_id +
                "' OR uuid IN (" + ", ".join("'" + item + "'" for item in sorted(uuids)) + "))")
    return {"rows": "SELECT " + ", ".join(READBACK_COLUMNS) + " FROM events WHERE " + selector +
                    " ORDER BY timestamp, uuid LIMIT 500",
            "count": "SELECT count() AS raw_count FROM events WHERE " + selector,
            "window": {"start_utc": begin.isoformat(), "end_utc": end.isoformat(),
                       "clock_margin_seconds": 300, "outward_whole_second_rounding": True}}


def expected_query(transport, preflight):
    return expected_queries(transport, preflight)["rows"]


def normalize_connector_rows(columns, rows):
    """Normalize an already-extracted connector table without dropping any row.

    The caller retains/hash-references the original connector response privately;
    this function does not authenticate that response or parse display screenshots.
    """
    if columns != READBACK_COLUMNS or not isinstance(rows, list):
        raise TrialBlocked("CONNECTOR_COLUMNS_INVALID")
    normalized = []
    for row in rows:
        if not isinstance(row, list) or len(row) != len(columns):
            raise TrialBlocked("CONNECTOR_ROW_WIDTH_INVALID")
        value = dict(zip(columns, row))
        if isinstance(value["properties"], str):
            value["properties"] = parse_json(value["properties"])
        if not isinstance(value["properties"], dict):
            raise TrialBlocked("CONNECTOR_PROPERTIES_INVALID")
        normalized.append(value)
    return normalized


def canonical_time(value):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9TZtz:.+\- ]{10,40}", value):
        raise TrialBlocked("TIMESTAMP_INVALID")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00").replace("z", "+00:00"))
    except ValueError as exc:
        raise TrialBlocked("TIMESTAMP_INVALID") from exc
    if parsed.tzinfo is None:
        raise TrialBlocked("TIMESTAMP_TIMEZONE_MISSING")
    return parsed.astimezone(timezone.utc).isoformat()


def public_shape(value):
    """Use the existing redactor, representing keys as names rather than fields.

    A cloud property named token/url/api_key remains reviewable without creating
    a credential-shaped public JSON field. Unknown scalar values stay redacted.
    """
    def convert(redacted):
        if isinstance(redacted, dict):
            return {"type": "object", "fields": [
                {"name": safe_name(name), "shape": convert(item)} for name, item in sorted(redacted.items())]}
        if isinstance(redacted, list):
            return {"type": "array", "items": [convert(item) for item in redacted]}
        return redacted
    return convert(shape(value))


def safe_name(value):
    name = key(value)
    try:
        validate_public_value(name)
    except TrialBlocked:
        return "<name-sha256:" + hashlib.sha256(str(value).encode()).hexdigest() + ">"
    return name


def transport_provenance(transport):
    if (transport.get("scope") != SOURCE_SCOPE or
            transport.get("project_id") != PROJECT or
            not re.fullmatch(r"[a-f0-9]{40}", transport.get("source_commit", ""))):
        raise TrialBlocked("TRANSPORT_PROVENANCE_INVALID")
    run_id = transport.get("run_id")
    event(run_id, 1)
    return run_id


def client_evidence(transport, preflight, attempts):
    """Recompute the row budget and stable retry identity from exported receipts."""
    run_id = transport_provenance(transport)
    if transport.get("status") != "TRANSPORT_COMPLETE_READBACK_PENDING" or transport.get("failures"):
        raise TrialBlocked("TRANSPORT_NOT_COMPLETE")
    budget = transport.get("budget", {})
    values = [budget.get(name) for name in ("reserved_rows", "limit", "total_ceiling", "prior_rows_reserved")]
    if (any(type(value) is not int for value in values) or values[2] != 500 or
            not 0 <= values[3] <= 500 or not 1 <= values[1] <= 500 or
            not 0 < values[0] <= values[1] or values[3] + values[1] > 500):
        raise TrialBlocked("TRANSMISSION_BUDGET_NOT_ATTESTED")
    by_attempt, originals, uuid_owners, reserved = {}, {}, {}, 0
    for receipt in preflight:
        attempt = receipt.get("attempt_id")
        if type(attempt) is not int or attempt <= 0 or attempt in by_attempt:
            raise TrialBlocked("PREFLIGHT_ATTEMPT_ID_INVALID")
        payload = receipt.get("payload")
        if (receipt.get("credential_redacted") is not True or
                receipt.get("envelope_keys") != ["api_key", "batch"] or
                not isinstance(payload, dict) or set(payload) != {"batch"}):
            raise TrialBlocked("PREFLIGHT_REDACTION_OR_ENVELOPE_INVALID")
        audit = audit_payload(dict(payload, api_key=TOKEN), run_id)
        if audit["violations"] or receipt.get("rows") != len(audit["normalized_rows"]):
            raise TrialBlocked("PREFLIGHT_CONTRACT_INVALID")
        reserved += receipt["rows"]
        if receipt.get("budget_reserved_rows") != reserved or reserved > budget["limit"]:
            raise TrialBlocked("PREFLIGHT_BUDGET_SEQUENCE_INVALID")
        by_attempt[attempt] = receipt
        for item in payload["batch"]:
            identity = item["properties"]["event_id"]
            uuid_value = item["uuid"].lower()
            if uuid_value in uuid_owners and uuid_owners[uuid_value] != identity:
                raise TrialBlocked("CLIENT_UUID_REUSED_FOR_DIFFERENT_EVENT_IDS")
            uuid_owners[uuid_value] = identity
            if identity in originals and originals[identity] != item:
                raise TrialBlocked("CLIENT_EVENT_CHANGED_ACROSS_ATTEMPTS")
            originals[identity] = item
    if not by_attempt or reserved != budget["reserved_rows"]:
        raise TrialBlocked("BUDGET_AND_PREFLIGHT_DISAGREE")
    phases, records, written, ignored = defaultdict(list), defaultdict(dict), Counter(), []
    for record in attempts:
        attempt = record.get("attempt_id")
        if type(attempt) is not int or attempt not in by_attempt:
            raise TrialBlocked("TRANSPORT_ATTEMPT_WITHOUT_PREFLIGHT")
        receipt = by_attempt[attempt]
        items = receipt["payload"]["batch"]
        if (record.get("rows") != len(items) or
                record.get("event_ids") != [item["properties"]["event_id"] for item in items] or
                record.get("uuids") != [item["uuid"] for item in items] or
                record.get("budget_reserved_rows") != receipt["budget_reserved_rows"]):
            raise TrialBlocked("TRANSPORT_AND_PREFLIGHT_DISAGREE")
        phase = record.get("phase")
        if phase not in ("reserved", "body_written", "response", "finished") or phase in phases[attempt]:
            raise TrialBlocked("TRANSPORT_PHASE_INVALID_OR_DUPLICATE")
        phases[attempt].append(phase)
        records[attempt][phase] = record
        if phase == "body_written":
            written.update(record["event_ids"])
        if phase == "response":
            if (type(record.get("response_code")) is not int or
                    type(record.get("response_accepted")) is not bool or
                    type(record.get("quota_limited")) is not bool or record["quota_limited"]):
                raise TrialBlocked("CLOUD_RESPONSE_ACCEPTANCE_OR_QUOTA_INVALID")
            if record["response_code"] == 200 and record["response_accepted"] is not True:
                raise TrialBlocked("CLOUD_200_RESPONSE_NOT_ACCEPTED")
        if phase == "response" and record.get("ack_discarded") is True:
            if record.get("response_code") != 200 or record.get("response_accepted") is not True:
                raise TrialBlocked("CONTROLLED_ACK_IGNORE_INVALID")
            ignored.append(record["event_ids"])
    for attempt in by_attempt:
        actual = phases[attempt]
        if (not actual or actual[0] != "reserved" or actual[-1] != "finished" or
                actual != sorted(actual, key=("reserved", "body_written", "response", "finished").index) or
                ("response" in actual and "body_written" not in actual)):
            raise TrialBlocked("TRANSPORT_PHASE_SEQUENCE_INCOMPLETE")
        final = records[attempt]["finished"]
        response = records[attempt].get("response", {})
        if (final.get("body_written") is not ("body_written" in actual) or
                final.get("ack_discarded") is not response.get("ack_discarded", False) or
                type(final.get("acknowledged")) is not bool or
                (final["acknowledged"] and (response.get("response_accepted") is not True or
                                            response.get("ack_discarded") is True))):
            raise TrialBlocked("TRANSPORT_FINISH_STATE_INCONSISTENT")
    expected_ids = {event(run_id, n)["event_id"] for n in (*range(1, 101), *range(121, 141))}
    revoked_ids = {event(run_id, n)["event_id"] for n in range(101, 121)}
    retry_ids = [event(run_id, n)["event_id"] for n in range(131, 141)]
    if (set(originals) != expected_ids or set(written) != expected_ids or
            set(originals) & revoked_ids or ignored != [retry_ids] or
            any(written[identity] < 2 for identity in retry_ids) or
            transport.get("retry_same_uuid_attested") is not True):
        raise TrialBlocked("CLIENT_COHORT_OR_CONTROLLED_RETRY_NOT_ATTESTED")
    return originals, {"reserved_rows": reserved, "limit": budget["limit"],
                       "prior_rows_reserved": budget["prior_rows_reserved"], "total_ceiling": 500,
                       "body_written_rows": sum(written.values()), "written_rows_per_id": dict(written),
                       "ignored_200_response_count": len(ignored),
                       "http_success_is_not_receipt": True}


def validate_readback(readback, transport, queries):
    if (not isinstance(readback, dict) or type(readback.get("schema_version")) is not int or
            readback.get("schema_version") != 1 or
            readback.get("project_id") != PROJECT or readback.get("run_id") != transport["run_id"] or
            readback.get("source_commit") != transport["source_commit"]):
        raise TrialBlocked("READBACK_PROVENANCE_MISMATCH")
    for field, expected in (("query", queries["rows"]), ("count_query", queries["count"])):
        query = readback.get(field)
        if not isinstance(query, str) or " ".join(query.split()) != " ".join(expected.split()):
            raise TrialBlocked("READBACK_QUERY_NOT_RAW_COMPLETE_RUN")
    observed = datetime.fromisoformat(canonical_time(readback.get("queried_at_utc")))
    if observed < datetime.fromisoformat(canonical_time(transport.get("finished_utc"))):
        raise TrialBlocked("READBACK_PREDATES_TRANSPORT_END")
    for prefix in ("row", "count"):
        ref = readback.get(prefix + "_response_ref")
        digest = readback.get(prefix + "_response_sha256")
        if (not isinstance(ref, str) or not 1 <= len(ref) <= 512 or
                not isinstance(digest, str) or not re.fullmatch(r"[a-f0-9]{64}", digest)):
            raise TrialBlocked("CONNECTOR_RESPONSE_PROVENANCE_MISSING")
    if (readback.get("complete") is not True or not isinstance(readback.get("rows"), list) or
            type(readback.get("raw_count")) is not int or not 0 <= readback["raw_count"] <= 500 or
            readback["raw_count"] != len(readback["rows"])):
        raise TrialBlocked("READBACK_INCOMPLETE_OR_LIMIT_REACHED")


def reconcile_trial(transport, preflight, attempts, readback=None):
    result = {"schema_version": 1, "scope": OUTPUT_SCOPE, "status": "BLOCKED",
              "project_id": PROJECT, "cloud_receipt_is_http_success": False,
              "observation_limit": "FINITE_QUERY_WINDOW_NOT_ALL_FUTURE_INGESTION",
              "selection_limit": "IDENTITY_MUTATIONS_OUTSIDE_TIMESTAMP_WINDOW_NOT_RULED_OUT",
              "cloud_mutation_does_not_imply_outbound_privacy_failure": True,
              "metadata_values_redacted": True, "failures": []}
    safe_rows = []
    try:
        run_id = transport_provenance(transport)
        queries = expected_queries(transport, preflight)
        result.update(run_id=run_id, source_commit=transport["source_commit"],
                      query=queries["rows"], count_query=queries["count"], query_window=queries["window"])
        client_error = None
        try:
            originals, budget = client_evidence(transport, preflight, attempts)
            result["budget"] = budget
        except (TrialBlocked, ValueError, TypeError, KeyError) as failure:
            client_error = str(failure) if isinstance(failure, TrialBlocked) else "CLIENT_EVIDENCE_SCHEMA_INVALID"
            originals = {}
            # Preserve diagnostic readback after partial sends. These recovered
            # items support comparison only, never restore an acceptance PASS.
            for receipt in preflight:
                payload = receipt.get("payload", {}) if isinstance(receipt, dict) else {}
                if isinstance(payload, dict) and set(payload) == {"batch"}:
                    audit = audit_payload(dict(payload, api_key=TOKEN), run_id)
                    if not audit["violations"]:
                        for item in payload["batch"]:
                            originals.setdefault(item["properties"]["event_id"], item)
            result["client_evidence_failure"] = client_error
        result["client_evidence_complete"] = client_error is None
        if readback is None:
            result["status"] = "BLOCKED" if client_error else "PENDING_READBACK"
            if client_error:
                result["blocked_reason"] = client_error
            return result, safe_rows
        validate_readback(readback, transport, queries)
        result["queried_at_utc"] = canonical_time(readback["queried_at_utc"])
        result["connector_response_provenance"] = {
            prefix: {"sha256": readback[prefix + "_response_sha256"],
                     "reference_sha256": hashlib.sha256(readback[prefix + "_response_ref"].encode()).hexdigest()}
            for prefix in ("row", "count")}
        result["raw_count_query"] = readback["raw_count"]
        result["source_authentication_limit"] = "REFERENCED_CONNECTOR_RECEIPTS_NOT_CRYPTOGRAPHIC_ATTESTATION"
        normalized, extras, errors = [], Counter(), Counter()
        for index, raw in enumerate(readback["rows"]):
            safe = {"row_index": index, "violations": [], "server_metadata": []}
            safe_rows.append(safe)
            if not isinstance(raw, dict) or set(raw) != READBACK_KEYS:
                safe["violations"].append("ROW_COLUMNS_INVALID")
                safe["row_shape"] = public_shape(raw)
                errors.update(safe["violations"])
                continue
            for name in ("person_mode", "person_id"):
                if raw[name] is not None:
                    label = "column:" + name
                    extras[label] += 1
                    safe["server_metadata"].append({"name": label, "present": True,
                                                     "value_shape": public_shape(raw[name])})
            try:
                safe["created_at"] = canonical_time(raw["created_at"])
            except TrialBlocked:
                safe["created_at"] = "<redacted>"
                safe["violations"].append("CLOUD_CREATED_AT_INVALID")
            properties = raw["properties"]
            if not isinstance(properties, dict):
                safe["violations"].append("PROPERTIES_NOT_OBJECT")
                safe["properties_shape"] = public_shape(properties)
                errors.update(safe["violations"])
                continue
            for name in sorted(set(properties) - PROPERTIES, key=str):
                label = safe_name(name)
                extras[label] += 1
                safe["server_metadata"].append({"name": label, "value_shape": public_shape(properties[name])})
            business = {name: properties.get(name) for name in FIELDS}
            try:
                validate(business)
                if business["run_id"] != run_id:
                    raise ValueError("Wrong synthetic run")
            except (ValueError, TypeError):
                safe["violations"].append("BUSINESS_CONTRACT_OR_RUN_INVALID")
                safe["business_shape"] = public_shape(business)
                errors.update(safe["violations"])
                continue
            normalized.append(business)
            safe["business"] = business
            for name, expected in (("$geoip_disable", True), ("$process_person_profile", False)):
                if properties.get(name) is not expected:
                    safe["violations"].append("CLOUD_STORED_PRIVACY_CONTROL_CHANGED:" + name)
            safe["event"] = "cm_lab_probe" if raw["event"] == "cm_lab_probe" else "<redacted>"
            safe["distinct_id"] = run_id if raw["distinct_id"] == run_id else "<redacted>"
            if raw["event"] != "cm_lab_probe" or raw["distinct_id"] != run_id:
                safe["violations"].append("EVENT_OR_DISTINCT_ID_CHANGED")
            original = originals.get(business["event_id"])
            safe["uuid"] = (raw["uuid"] if is_uuid(raw["uuid"]) and original is not None
                            and raw["uuid"].lower() == original["uuid"].lower() else "<redacted:unattested-uuid>")
            if not is_uuid(raw["uuid"]):
                safe["violations"].append("CLOUD_UUID_INVALID")
            try:
                safe["timestamp"] = canonical_time(raw["timestamp"])
                if not (queries["window"]["start_utc"] <= safe["timestamp"] <= queries["window"]["end_utc"]):
                    safe["violations"].append("CLOUD_TIMESTAMP_OUTSIDE_QUERY_WINDOW")
            except TrialBlocked:
                safe["timestamp"] = "<redacted>"
                safe["violations"].append("CLOUD_TIMESTAMP_INVALID")
            if original is None:
                safe["violations"].append("NO_CLIENT_BODY_FOR_CLOUD_EVENT")
            elif (str(raw["uuid"]).lower() != original["uuid"].lower() or
                  safe["timestamp"] != canonical_time(original["timestamp"])):
                safe["violations"].append("CLOUD_UUID_OR_TIMESTAMP_DIFFERS_FROM_CLIENT")
            errors.update(safe["violations"])
        expected = [event(run_id, n) for n in (*range(1, 101), *range(121, 141))]
        result["overall"] = reconcile(expected, normalized)
        result["raw_rows_seen"] = len(readback["rows"])
        result["invalid_rows"] = sum(bool(row["violations"]) for row in safe_rows)
        result["metadata_extra_key_counts"] = [{"name": name, "rows": count} for name, count in sorted(extras.items())]
        result["row_violation_counts"] = dict(errors)
        cohorts = {"normal": range(1, 101), "revoked": range(101, 121),
                   "new": range(121, 131), "retry": range(131, 141)}
        result["phases"] = {}
        for name, sequence in cohorts.items():
            actual = [row for row in normalized if row["sequence"] in sequence]
            wanted = [] if name == "revoked" else [event(run_id, n) for n in sequence]
            result["phases"][name] = reconcile(wanted, actual)
        retry_counts = Counter(row["event_id"] for row in normalized if 131 <= row["sequence"] <= 140)
        result["retry_storage_observation"] = {
            "rows_per_id": dict(retry_counts),
            "interpretation": "DUPLICATE_STORED_ROWS_OBSERVED" if any(v > 1 for v in retry_counts.values()) else
                              "ONE_OR_ZERO_STORED_ROWS_PER_ID_AFTER_MULTIPLE_CLIENT_BODY_WRITES",
            "universal_deduplication_guarantee": False}
        failures = result["failures"]
        if errors:
            failures.append("CLOUD_CONTENT_OR_PROTOCOL_CHANGED")
        if any(result["overall"][name] for name in ("missing_ids", "unexpected_ids", "conflicting_ids")):
            failures.append("EVENT_RECONCILIATION_FAILED")
        if any(result["phases"][name]["duplicate_rows"] for name in ("normal", "new")):
            failures.append("UNEXPECTED_NORMAL_OR_NEW_DUPLICATES")
        if result["phases"]["revoked"]["received_rows"]:
            failures.append("REVOKED_EVENTS_RECEIVED")
        result["delivery_pass"] = not failures
        result["metadata_review_required"] = bool(extras)
        result["person_fields_are_not_proof_of_profile_creation"] = True
        result["status"] = "BLOCKED" if client_error else "FAILED" if failures else "REVIEW_REQUIRED" if extras else "PASSED"
        if client_error:
            result["blocked_reason"] = client_error
    except (TrialBlocked, ValueError, TypeError, KeyError) as failure:
        result["status"] = "BLOCKED"
        result["blocked_reason"] = str(failure) if isinstance(failure, TrialBlocked) else "INPUT_SCHEMA_INVALID"
    return result, safe_rows


def parse_json(text):
    def unique(pairs):
        result = {}
        for name, value in pairs:
            if name in result:
                raise TrialBlocked("DUPLICATE_JSON_KEY")
            result[name] = value
        return result
    return json.loads(text, object_pairs_hook=unique,
                      parse_constant=lambda _: (_ for _ in ()).throw(TrialBlocked("NONFINITE_JSON")))


def load_json(path):
    if path.is_symlink() or path.stat().st_size > MAX_INPUT_BYTES:
        raise TrialBlocked("INPUT_FILE_TYPE_OR_SIZE_REJECTED")
    return parse_json(path.read_text())


def load_jsonl(path):
    if path.is_symlink() or path.stat().st_size > MAX_INPUT_BYTES:
        raise TrialBlocked("INPUT_FILE_TYPE_OR_SIZE_REJECTED")
    return [parse_json(line) for line in path.read_text().splitlines() if line]


def write_jsonl(path, rows):
    for row in rows:
        validate_public_value(row)
    path.write_text("".join(json.dumps(row, sort_keys=True, allow_nan=False) + "\n" for row in rows))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--transport", type=Path, required=True)
    parser.add_argument("--readback", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    try:
        transport = load_json(args.transport)
        preflight = load_jsonl(args.transport.parent / "preflight.jsonl")
        attempts = load_jsonl(args.transport.parent / "transport.jsonl")
        readback = load_json(args.readback) if args.readback else None
        result, rows = reconcile_trial(transport, preflight, attempts, readback)
        if "run_id" in result:
            run_id = result["run_id"]
            write_jsonl(args.out / "expected.jsonl", [event(run_id, n) for n in (*range(1, 101), *range(121, 141))])
            write_jsonl(args.out / "revoked-intent.jsonl", [event(run_id, n) for n in range(101, 121)])
            public_write(args.out / "query.json", {"project_id": PROJECT, **expected_queries(transport, preflight)})
        write_jsonl(args.out / "received.jsonl", rows)
    except (OSError, ValueError, TypeError, TrialBlocked) as failure:
        result = {"schema_version": 1, "scope": OUTPUT_SCOPE, "status": "BLOCKED",
                  "blocked_reason": str(failure) if isinstance(failure, TrialBlocked) else "INPUT_READ_FAILED"}
    public_write(args.out / "result.json", result)
    print(json.dumps({"status": result["status"], "raw_rows_seen": result.get("raw_rows_seen"),
                      "metadata_review_required": result.get("metadata_review_required")}))
    return 0 if result["status"] == "PASSED" else 1


if __name__ == "__main__":
    raise SystemExit(main())
