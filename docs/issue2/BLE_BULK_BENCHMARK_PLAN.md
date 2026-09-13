# Convoy Mesh — BLE bulk benchmark plan

Status: design/measurement plan only. No transport winner is assumed.

This plan exists to answer one narrow question from Issue #2 with physical evidence on the actual target phones: **which single bulk transport should Convoy use for ledger delta transfer, GATT or LE L2CAP CoC?**

It deliberately does not modify the 0.7.6+8 field candidate and does not treat API availability, nominal PHY bitrate, emulator results, or successful TX callbacks as proof of real phone-to-phone throughput.

## Target devices

Run both directions on the two already used Convoy targets:

- Mi 9 Lite / Android API 29;
- M2101K6G / Android API 33.

Record exact model, Android build, Bluetooth state, battery state, relevant OEM battery settings and runtime permissions for every campaign.

## Common rules

GATT and CoC must use:

- the same deterministic application payload bytes;
- the same block framing and final content digest;
- the same persistence/commit boundary when persistence is introduced;
- the same JSONL event schema;
- monotonic timestamps from the device where the measured event occurs;
- the same screen/power/GNSS conditions;
- the same test sizes and repetition counts.

A transport callback, completed write or socket write is **not** proof that the remote ledger committed the block. Completion is measured at the application commit boundary.

Do not compare one-way timestamps from unsynchronised phone clocks. Use local RTTs or timestamps measured on the same receiving device.

## Phase 0 — capabilities, not conclusions

For each phone log:

- legacy advertising support/path;
- `isLeExtendedAdvertisingSupported`;
- `isLeCodedPhySupported`;
- `isLe2MPhySupported`;
- `getLeMaximumAdvertisingDataLength`;
- actual success/failure when starting/updating each tested advertising mode;
- receive-side PHY / advertising SID / data status where available;
- LE CoC API availability and actual server/client open result;
- GATT client/server open result.

A reported capability is only a prerequisite. It is not counted as interoperability until the two physical phones exchange data successfully in both directions.

## Phase 1 — cold/warm setup and first useful committed record

For **each direction** A→B and B→A, and separately for GATT and CoC:

- 100 cold encounters;
- 100 warm encounters;
- secure/insecure variants only where they are actually supported and meaningful;
- forced contact budgets of approximately 1 s, 3 s and 10 s for the physical harness.

Measure:

- setup success/failure;
- p50 / p95 setup latency;
- time to first valid application block;
- time to first **committed** record;
- pairing prompts or other user interaction;
- disconnect reason / timeout reason;
- reconnect/resume behaviour.

Treat p99 from 100 samples as exploratory only. If a configuration becomes a finalist, repeat it at least 1,000 times before claiming tail behaviour.

## Phase 2 — bulk goodput and flow control

Use deterministic payload sizes:

- 1 kB;
- 8 kB;
- 80 kB;
- 160 kB.

Run at least ten repetitions per cell and direction.

### GATT variants

Measure at minimum:

- actual negotiated MTU 23;
- maximum MTU successfully negotiated on the target pair;
- application windows 1 / 4 / 8 blocks where safe;
- notifications / writes according to the chosen direction, with bounded queues.

Never infer usable application bytes from nominal MTU without recording the actual negotiated value and protocol overhead.

### CoC variants

Record:

- actual dynamic PSM lifecycle;
- `getMaxReceivePacketSize` / `getMaxTransmitPacketSize` where available;
- partial reads/writes;
- application chunk size;
- backpressure behaviour;
- close/reopen behaviour after process or Bluetooth restart.

### Common output

Measure:

- useful committed bytes/s;
- total application DATA attempted;
- control bytes;
- duplicate bytes;
- retransmitted blocks;
- setup overhead;
- maximum queued bytes / blocks;
- CPU time where measurable;
- process memory peak;
- final digest equality;
- number of missing records after completion.

## Phase 3 — screen off, idle and Doze

Repeat finalist configurations with:

- screen on;
- screen off;
- verified idle;
- forced Doze where the Android version permits a reproducible test;
- peer arriving while the receiver is already screen-off.

Observe for about 30 minutes per long-running configuration where practical.

Log separately:

- discovery latency;
- connection setup latency;
- first committed record latency;
- scanner/GNSS gaps;
- foreground-service state;
- native callbacks lost/delayed;
- recovery when the screen wakes;
- OEM-specific failures.

Do not describe forced Doze as equivalent to every OEM's natural power policy.

## Phase 4 — deterministic failure/recovery hooks

Exercise both candidate transports with reproducible faults:

- disconnect before application commit;
- process kill before commit;
- process kill after commit but before application ACK;
- ACK deliberately dropped;
- Bluetooth OFF/ON mid-transfer;
- connection closed halfway through a block;
- reconnect and resume from the same peer;
- reconnect and resume from a different carrier holding the same author-owned records.

Required logical result:

- no ACK for uncommitted records;
- committed records remain after restart;
- replay is idempotent;
- only missing records are requested after recovery;
- no author/session/point identity is rewritten by the relay;
- failure cause is explicit when automatic recovery is impossible.

## Phase 5 — Rescue contact measurements

This is separate from bulk selection, but can reuse the harness.

For the legacy 24-byte Rescue candidate and any supported Extended variant:

- enter receiver range at a random phase of the transmitter rotation;
- nominal advertising intervals 100 ms and 250 ms where supported by the chosen API/mode;
- collect physical windows of roughly 1 s, 3 s and 10 s;
- repeat with screen on/off;
- test 1, 2 and 3 received valid packets;
- deliberately include duplicates;
- deliberately truncate Extended data and verify it is rejected as complete trail data;
- include relayed observations whose original author is not physically nearby.

Measure:

- probability of at least one valid self-contained capsule;
- time to first useful capsule;
- number of distinct authors/observations learned;
- age/freshness correctness;
- false attribution of radio presence to a relayed author;
- truncated/invalid packet rejection.

Do not infer drone range or fly-by success from this bench alone; geometry, terrain, body shielding and actual drone hardware require separate field measurements.

## Phase 6 — energy

Keep GNSS, screen state, temperature and battery conditions as comparable as practical. Compare at least:

- GNSS/runtime baseline without bulk;
- legacy presence only;
- legacy + GATT bulk;
- legacy + CoC bulk.

Run at least three 30-minute sessions per configuration before drawing even preliminary conclusions.

Prefer energy per useful committed kB plus whole-outing energy. Battery percentage alone is a weak metric; use Android charge counters only if they behave consistently on the target device, otherwise use an external measurement method.

## Decision rule

Do **not** freeze GATT or CoC from API documentation or simulated rounds.

Choose one production bulk transport only after physical evidence, in this order:

1. correctness and recovery semantics;
2. interoperability in both directions on both target phones;
3. p95 time to first committed useful record;
4. committed useful goodput for 1/8/80/160 kB;
5. screen-off / power behaviour;
6. energy cost;
7. implementation and maintenance complexity.

If GATT and CoC are effectively tied within test noise, prefer the simpler single implementation. Do not maintain two production bulk paths without a measured need.

Extended Advertising remains complementary to discovery/Rescue unless physical data demonstrate a compelling additional role; it is not automatically a reliable bulk transport.

## Before 15–20 physical devices

Start with two phones to select and harden the transport. Then use at least four phones for relay/contention tests. Only after correctness, resume and basic fairness are measurable should the team spend effort on a 15–20-device physical campaign.

For the larger campaign capture per-author backlog, age of oldest missing record, fairness, duplicate connections, duplicate DATA, convergence scope and battery. A temporally disconnected graph is not a protocol failure; report unreachable scope separately from recoverable backlog.
