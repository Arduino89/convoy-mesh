import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'manual_ping_service.dart';
import 'diagnostic_test_context.dart';

/// Explicit one-request beta diagnostics. No SDK, queue, retry or raw JSONL upload.
class DetailedDiagnosticUpload {
  DetailedDiagnosticUpload._(this.sessionId, this.deviceId, this.deviceName,
      this.uploadId, this.events, this.peerLabels, this.excludedRecords, this.bytes);

  static const maxRecords = 1200;
  static const maxRequestBytes = 750000;
  static const endpoint = 'https://eu.i.posthog.com/batch/';
  static const eventName = 'cm_beta_diag_record';

  // A source-field allowlist, not a copy of the arbitrary JSONL data map.
  static const fields = <String, List<String>>{
    'session.start': ['schema_version', 'app_version', 'build_commit',
      'max_duration_ms', 'disk_buffer_max_ms', 'persistent_storage'],
    'session.stop': ['reason', 'events', 'dropped_events'],
    'test.context': ['source', 'environment', 'self_movement',
      'peers_movement', 'phone_placement', 'screen_reported'],
    'test.marker': ['source', 'marker'],
    'test.outcome': ['source', 'outcome'],
    'ble.status': ['status', 'mode'],
    'ble.nearby_started': [],
    'ble.nearby_stopped': [],
    'ble.refresh_requested': ['reason', 'mode'],
    'ble.status_error': [],
    'ble.scan_error': [],
    'ble.scan_restart': ['reason', 'count'],
    'ble.rx_parse_rejected': ['reason'],
    'ble.rx_packet': ['peer_id', 'seq', 'kind', 'rssi', 'source_age_s',
      'observed_elapsed_nanos', 'delivered_elapsed_nanos', 'native_scan_delay_ms'],
    'ble.rx_decision': ['peer_id', 'seq', 'kind', 'accepted_packet',
      'accepted_fix', 'accepted_history', 'accepted_history_ack', 'rejected_parts'],
    'ble.tx_requested': ['kind', 'seq', 'fix_source_utc', 'radio_ttl_ms'],
    'ble.tx_native_success': ['kind', 'seq', 'manufacturer_id'],
    'ble.tx_native_error': ['kind', 'seq', 'manufacturer_id'],
    'ble.tx_error': [],
    'ble.history_queued': ['peer_id', 'gap_seconds', 'queued_points', 'pending_total'],
    'ble.history_attempt': ['history_seq', 'attempt', 'target_peer_ids',
      'unacked_peer_ids'],
    'ble.history_abandoned': ['history_seq', 'attempts', 'unacked_peer_ids'],
    'ble.history_acknowledged': ['history_seq', 'peer_id', 'attempts',
      'remaining_peer_ids'],
    'ble.history_ack_queue_evicted': ['target_user_id', 'history_seq', 'limit'],
    'ble.history_queue_saturated': ['peer_id', 'limit'],
    'ble.history_cleared_with_local_trail': [],
    'gps.fix': ['source_ts_utc', 'received_ts_utc', 'coordinate_ts_utc',
      'supported_ts_utc', 'raw_lat', 'raw_lon', 'raw_accuracy_m',
      'display_lat', 'display_lon', 'accuracy_m', 'decision', 'fresh',
      'track_added', 'track_points_total', 'record_track', 'moving',
      'motion_reliable', 'motion_score', 'gps_ready'],
    'gps.position_request': ['record_track'],
    'gps.mode_transition': ['reason', 'outing_started_utc', 'supported_ts_utc',
      'fresh', 'gps_ready', 'record_track'],
    'gps.service_status': ['enabled', 'permission'],
    'gps.service_status_error': [],
    'gps.stream_error': [],
    'gps.stream_start_error': [],
    'runtime.snapshot': ['foreground_service', 'mesh_running', 'outing_active',
      'ble_status', 'scanning', 'advertising', 'rx_valid_total', 'rx_stale_total',
      'scan_events_total', 'tx_ok_total', 'tx_error_total',
      'pending_history_points', 'pending_history_acks', 'rx_history_ack_total',
      'local_fix_fresh', 'local_trail_points', 'local_trail_last_utc', 'peers'],
    'runtime.outing_mode': ['active'],
    'runtime.foreground_service_started': ['verified_running'],
    'runtime.foreground_service_stopped': [],
    'runtime.foreground_service_error': [],
    'lifecycle.screen_unlocked': [],
    'motion.state_change': ['moving', 'score', 'reliable', 'reason'],
    'motion.sensor_error': [],
    'capability.device': ['sdk_int', 'model', 'uwb', 'wifi_rtt',
      'ble_extended_advertising', 'ble_multiple_advertising',
      'ranging_active', 'foreground_runtime_running'],
  };

  final String sessionId, deviceName, uploadId;
  final int deviceId, excludedRecords, bytes;
  final List<Map<String, Object?>> events;
  final Map<int, String> peerLabels;
  int get recordCount => events.length;

  /// Exact events proposed for transmission. Project write token is omitted.
  Map<String, Object> get preview => {
    'endpoint': endpoint, 'upload_id': uploadId,
    'included_records': recordCount, 'excluded_records': excludedRecords,
    'batch': events,
  };

  static DetailedDiagnosticUpload fromJsonl(String jsonl,
      {String? uploadIdOverride}) {
    final uploadId = uploadIdOverride ?? ManualPingService.newPingId();
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(uploadId)) {
      throw const FormatException('ID invio non valido');
    }
    final lines = const LineSplitter().convert(jsonl)
        .where((s) => s.trim().isNotEmpty).toList(growable: false);
    if (lines.isEmpty || lines.length > 20000) {
      throw const FormatException('Log vuoto o troppo grande');
    }
    String? session, name;
    int? device;
    var starts = 0, stops = 0, excluded = 0, lastIndex = -1;
    final peers = <int, String>{};
    final events = <Map<String, Object?>>[];

    for (final line in lines) {
      Object? decoded;
      try {
        decoded = jsonDecode(line);
      } on FormatException {
        throw const FormatException('Record JSONL malformato');
      }
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Record JSONL non valido');
      }
      final sid = decoded['session_id'];
      final did = decoded['device_id'];
      final nickname = decoded['device_name'];
      final index = decoded['event_index'];
      final elapsed = decoded['elapsed_ms'];
      final timestamp = decoded['ts_utc'];
      if (sid is! String || sid.isEmpty || sid.length > 90 ||
          did is! int || did <= 0 || nickname is! String ||
          nickname.isEmpty || nickname.length > 80 ||
          index is! int || index <= lastIndex ||
          elapsed is! int || elapsed < 0 || elapsed > 86400000 ||
          timestamp is! String ||
          DateTime.tryParse(timestamp)?.isUtc != true) {
        throw const FormatException('Identità, ordine o tempi del log non validi');
      }
      session ??= sid; device ??= did; name ??= nickname;
      if (sid != session || did != device || nickname != name) {
        throw const FormatException('Il file contiene più sessioni o dispositivi');
      }
      lastIndex = index;

      final category = decoded['category'];
      final action = decoded['event'];
      if (category is! String || action is! String) {
        throw const FormatException('Tipo record mancante');
      }
      final type = '$category.$action';
      if (type == 'session.start') starts++;
      if (type == 'session.stop') stops++;
      final allowed = fields[type];
      if (allowed == null) {
        // User-entered notes and unknown future fields stay on the phone.
        excluded++;
        continue;
      }
      final source = decoded['data'];
      if (source != null && source is! Map) {
        throw const FormatException('Dati record non validi');
      }
      final data = source is Map ? source : const <String, Object?>{};
      if (category == 'test' && !DiagnosticTestContext.validate(action, data)) {
        throw const FormatException('Contesto dichiarato dal tester non valido');
      }
      final props = <String, Object?>{
        r'$process_person_profile': false,
        r'$geoip_disable': true,
        'schema_version': 1, 'upload_id': uploadId,
        // For PostHog /batch/ distinct_id belongs inside properties.
        'distinct_id': 'cm-beta-device-$did',
        'session_id': sid, 'device_id': did, 'device_name': nickname,
        'event_index': index, 'captured_ts_utc': timestamp,
        'elapsed_ms': elapsed, 'category': category, 'action': action,
      };
      for (final key in allowed) {
        if (key == 'peers') {
          final values = data['peers'];
          if (values is! List) continue;
          if (values.length > 128) throw const FormatException('Troppi peer');
          final snapshots = <Map<String, Object?>>[];
          for (final peer in values) {
            if (peer is! Map || peer['id'] is! int ||
                (peer['id'] as int) <= 0) {
              throw const FormatException('Identità peer non valida');
            }
            final id = peer['id'] as int;
            final label = peer['name'] is String
                ? peer['name'] as String : 'ID $id';
            if (label.length > 80) throw const FormatException('Nickname troppo lungo');
            peers[id] = label;
            final p = <String, Object?>{'id': id, 'name': label};
            for (final field in const ['online', 'rssi', 'median_rssi',
              'last_seq', 'lat', 'lon', 'accuracy_m', 'last_seen_utc',
              'last_heard_utc', 'last_fix_received_utc',
              'last_fix_source_utc', 'fix_fresh']) {
              final v = _safeValue(field, peer[field]);
              if (v != null) p[field] = v;
            }
            snapshots.add(p);
          }
          props['peers'] = snapshots;
        } else {
          final v = _safeValue(key, data[key]);
          if (v != null) props[key] = v;
        }
      }
      for (final key in const ['peer_id', 'target_user_id']) {
        final id = data[key];
        if (id is int && id > 0) {
          peers.putIfAbsent(id, () => 'ID $id');
        }
      }
      for (final key in const ['target_peer_ids', 'unacked_peer_ids',
          'remaining_peer_ids']) {
        final ids = data[key];
        if (ids is List) {
          for (final id in ids.whereType<int>()) {
            if (id > 0) peers.putIfAbsent(id, () => 'ID $id');
          }
        }
      }
      events.add({
        'event': eventName,
        'properties': props,
      });
    }
    if (starts != 1 || stops != 1 || session == null ||
        device == null || name == null) {
      throw const FormatException('Sessione senza un unico avvio e termine');
    }
    if (events.isEmpty || events.length > maxRecords) {
      throw const FormatException('Troppi record: condividi il file locale');
    }
    // Explicit transfer manifest on the terminal record. Original event indices
    // remain intact; allowlist exclusions are distinct from transport losses.
    final terminal = events.singleWhere((e) {
      final props = e['properties'] as Map<String, Object?>;
      return props['category'] == 'session' && props['action'] == 'stop';
    })['properties'] as Map<String, Object?>;
    terminal['upload_record_count'] = events.length;
    terminal['upload_excluded_count'] = excluded;
    final estimate = utf8.encode(jsonEncode({
      'token': 'phc_placeholder_for_size_verification_123456789',
      'batch': events,
    })).length;
    if (estimate > maxRequestBytes) {
      throw const FormatException('Invio troppo grande: condividi il file locale');
    }
    return DetailedDiagnosticUpload._(session, device, name, uploadId,
        List.unmodifiable(events), Map.unmodifiable(peers), excluded, estimate);
  }

  static Object? _safeValue(String key, Object? value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) {
      if (!value.isFinite) throw const FormatException('Numero non finito');
      if ((key == 'lat' || key.endsWith('_lat')) &&
          (value < -90 || value > 90)) {
        throw const FormatException('Latitudine non valida');
      }
      if ((key == 'lon' || key.endsWith('_lon')) &&
          (value < -180 || value > 180)) {
        throw const FormatException('Longitudine non valida');
      }
      return value;
    }
    if (value is String) {
      if (key.endsWith('_utc')) {
        if (value.length > 40 || DateTime.tryParse(value) == null) {
          throw const FormatException('Data non valida');
        }
        return value;
      }
      if (key == 'name') return value.length <= 80 ? value : value.substring(0, 80);
      // Arbitrary notes, errors and raw radio payloads cannot pass this gate.
      if (value.length <= 64 &&
          RegExp(r'^[A-Za-z0-9_:+.\-]+$').hasMatch(value)) return value;
      return null;
    }
    if (value is List && value.length <= 32) {
      if (key.endsWith('_ids') &&
          value.every((x) => x is int && x > 0)) {
        return List<int>.from(value);
      }
      if (key == 'rejected_parts' && value.every((x) =>
          x is String && x.length <= 64 &&
          RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(x))) {
        return List<String>.from(value);
      }
    }
    return null;
  }
}

/// Immutable snapshot of a single-shot detailed diagnostic upload attempt.
class DetailedDiagnosticUploadAttemptRecord {
  const DetailedDiagnosticUploadAttemptRecord({
    required this.uploadId,
    this.attempted = false,
    this.inFlight = false,
    this.status,
    this.ownerConsent = false,
    this.ackStoredData = false,
    this.approvedPeers = const <int>{},
  });

  final String uploadId;
  final bool attempted;
  final bool inFlight;
  final String? status;
  final bool ownerConsent;
  final bool ackStoredData;
  final Set<int> approvedPeers;
}

/// Process-scoped, in-memory-only single-shot ledger for detailed diagnostic
/// uploads. Never persists consent to disk and never retries; survives
/// ListView evictions, style switches, and mid-flight widget unmounts.
class DetailedDiagnosticUploadAttemptStore extends ChangeNotifier {
  final Map<String, DetailedDiagnosticUploadAttemptRecord> _records = {};

  /// Deterministic fingerprint combining session ID, UTF-8 length, and two
  /// independent 32-bit hashes so distinct sessions/captures never collide.
  static String fingerprintFor(String sessionId, String jsonl) {
    var fnv = 0x811c9dc5;
    var djb = 5381;
    final bytes = utf8.encode(jsonl);
    for (final b in bytes) {
      fnv ^= b;
      fnv = (fnv * 0x01000193) & 0xFFFFFFFF;
      djb = (((djb << 5) + djb) ^ b) & 0xFFFFFFFF;
    }
    return '$sessionId|${bytes.length}|'
        '${fnv.toRadixString(16).padLeft(8, '0')}'
        '${djb.toRadixString(16).padLeft(8, '0')}';
  }

  DetailedDiagnosticUploadAttemptRecord? recordFor(String key) => _records[key];

  bool beginAttempt(
    String key, {
    required String uploadId,
    required bool ownerConsent,
    required bool ackStoredData,
    required Set<int> approvedPeers,
  }) {
    final existing = _records[key];
    if (existing != null && (existing.attempted || existing.inFlight)) {
      return false;
    }
    _records[key] = DetailedDiagnosticUploadAttemptRecord(
      uploadId: existing?.uploadId ?? uploadId,
      attempted: true,
      inFlight: true,
      status: 'Un unico invio HTTPS in corso…',
      ownerConsent: ownerConsent,
      ackStoredData: ackStoredData,
      approvedPeers: Set<int>.unmodifiable(approvedPeers),
    );
    notifyListeners();
    return true;
  }

  void completeAttempt(String key, String status) {
    final existing = _records[key];
    if (existing == null || !existing.attempted) return;
    _records[key] = DetailedDiagnosticUploadAttemptRecord(
      uploadId: existing.uploadId,
      attempted: true,
      inFlight: false,
      status: status,
      ownerConsent: existing.ownerConsent,
      ackStoredData: existing.ackStoredData,
      approvedPeers: existing.approvedPeers,
    );
    notifyListeners();
  }

  @visibleForTesting
  void reset() {
    _records.clear();
    notifyListeners();
  }
}

/// One HTTPS POST, no persisting, queue, retry or SDK tracking.
class DetailedDiagnosticUploadSender {
  static const String _token = String.fromEnvironment(
      'CONVOY_POSTHOG_PROJECT_TOKEN');
  static bool get temporarilyDisabled => ManualPingService.temporarilyDisabled;
  static bool get configured => ManualPingService.isConfigured;
  static final DetailedDiagnosticUploadAttemptStore attemptStore =
      DetailedDiagnosticUploadAttemptStore();

  @visibleForTesting
  static void resetAttemptsForTest() => attemptStore.reset();

  static Map<String, Object> requestBody(
      DetailedDiagnosticUpload candidate, String token) {
    if (!ManualPingService.validProjectToken(token)) {
      throw const FormatException('Token di progetto non valido');
    }
    return {'token': token, 'batch': candidate.events};
  }

  /// HTTP success does not prove PostHog stored the events. Use upload_id for
  /// readback; avoid retriggering after ambiguous timeouts.
  static Future<int> sendOnce(DetailedDiagnosticUpload candidate) async {
    if (temporarilyDisabled) {
      throw StateError(
          'Invio PostHog temporaneamente disattivato in questa build');
    }
    if (!configured) throw StateError('Token PostHog EU non configurato');
    final bytes = utf8.encode(jsonEncode(requestBody(candidate, _token)));
    if (bytes.length > DetailedDiagnosticUpload.maxRequestBytes) {
      throw StateError('Dimensione upload oltre il limite');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .postUrl(Uri.parse(DetailedDiagnosticUpload.endpoint))
          .timeout(const Duration(seconds: 12));
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close()
          .timeout(const Duration(seconds: 20));
      final status = response.statusCode;
      await response.drain<void>().timeout(const Duration(seconds: 12));
      return status;
    } finally {
      client.close(force: true);
    }
  }
}
