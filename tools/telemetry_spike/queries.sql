-- Templates. Concrete executed cloud-control queries are in the evidence receipts.
-- One isolated test project; substitute the exact run ID. Never query real users.
-- PostHog HogQL: per-event multiplicity; compare against the local expected IDs.
SELECT properties.event_id AS event_id, count() AS received_rows
FROM events
WHERE event = 'cm_lab_probe'
  AND timestamp >= '2026-11-01 00:00:00'
  AND timestamp < '2026-11-02 00:00:00'
  AND properties.run_id = 'synthetic-REPLACE-RUN-ID'
GROUP BY event_id
ORDER BY event_id
LIMIT 500;

-- PostHog ad-hoc detail, capped to this small trial; not an ETL/export service.
SELECT properties.schema_version AS schema_version,
       properties.run_id AS run_id,
       properties.event_id AS event_id,
       properties.sequence AS sequence,
       properties.event_name AS event_name,
       properties.synthetic AS synthetic,
       properties.$geoip_disable AS geoip_disabled
FROM events
WHERE event = 'cm_lab_probe'
  AND timestamp >= '2026-11-01 00:00:00'
  AND timestamp < '2026-11-02 00:00:00'
  AND properties.run_id = 'synthetic-REPLACE-RUN-ID'
ORDER BY properties.sequence
LIMIT 500;
-- If results hit the limit or the query is partial/cached before reconnect, STOP.
-- Keep all rows including duplicates. Normalize only explicit scalar types to
-- the six-field JSONL schema; pass to probe.py reconcile. Do not invent rows.
-- Fetch current results after reconnect; keep query ID/time + result receipt.

-- BigQuery Standard SQL alternative: replace project/dataset/date/run.
-- Daily tables ONLY: mixing intraday and daily can duplicate the same event.
-- This query presumes the same schema, with synthetic=1 (GA event params have
-- int/string/double types, not a native boolean); normalize it explicitly later.
WITH lab AS (
 SELECT
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key='schema_version') AS schema_version,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key='run_id') AS run_id,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key='event_id') AS event_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key='sequence') AS sequence,
  event_name,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key='synthetic') AS synthetic_int
 FROM `REPLACE_PROJECT.REPLACE_DATASET.events_*`
 WHERE _TABLE_SUFFIX BETWEEN '20261101' AND '20261104'
   AND event_name='cm_lab_probe'
)
SELECT schema_version, run_id, event_id, sequence, event_name,
       synthetic_int=1 AS synthetic
FROM lab
WHERE run_id='synthetic-REPLACE-RUN-ID'
ORDER BY sequence
LIMIT 5001;
-- Missing at the first query means PENDING until the export observation window
-- closes. Inspect export freshness, active data filters and SDK errors first.
