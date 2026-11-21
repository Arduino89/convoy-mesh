import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// Immutable snapshot of the launch-scoped manual ping attempt.
class ManualPingAttemptState {
  const ManualPingAttemptState({
    this.attempted = false,
    this.inFlight = false,
    this.pingId,
    this.status,
  });

  final bool attempted;
  final bool inFlight;
  final String? pingId;
  final String? status;
}

/// Process-scoped, in-memory-only single-shot guard for manual ping attempts.
/// Never persisted to disk and never retries; survives widget unmounts,
/// ListView evictions, and style switches within the same app launch.
class ManualPingAttemptTracker extends ChangeNotifier {
  ManualPingAttemptState _state = const ManualPingAttemptState();

  ManualPingAttemptState get state => _state;

  bool beginAttempt(String pingId) {
    if (_state.attempted || _state.inFlight) return false;
    _state = ManualPingAttemptState(
      attempted: true,
      inFlight: true,
      pingId: pingId,
      status: 'Invio singolo in corso…',
    );
    notifyListeners();
    return true;
  }

  void completeAttempt(String status) {
    if (!_state.attempted) return;
    _state = ManualPingAttemptState(
      attempted: true,
      inFlight: false,
      pingId: _state.pingId,
      status: status,
    );
    notifyListeners();
  }

  @visibleForTesting
  void reset() {
    _state = const ManualPingAttemptState();
    notifyListeners();
  }
}

/// Single explicit, synthetic connectivity probe. Never reads GPS, BLE, names,
/// diagnostic files, persistent identifiers or any other application state.
class ManualPingService {
  // Compile-time ingestion-only public project token, never tracked in git.
  static const String _buildToken =
      String.fromEnvironment('CONVOY_POSTHOG_PROJECT_TOKEN');
  // Explicit compile-time pause switch used by builds where PostHog upload is
  // intentionally disabled while keeping reactivation clean via build flags.
  static const bool temporarilyDisabled =
      bool.fromEnvironment('CONVOY_POSTHOG_TEMPORARILY_DISABLED');
  static bool get isConfigured =>
      !temporarilyDisabled &&
      validProjectToken(_buildToken) &&
      _buildToken != 'phc_synthetic_local_only';
  static final ManualPingAttemptTracker attemptTracker =
      ManualPingAttemptTracker();
  static final RegExp _tokenPattern = RegExp(r'^phc_[A-Za-z0-9_-]{16,200}$');
  static final RegExp _idPattern = RegExp(r'^[a-f0-9]{32}$');
  static final Uri _endpoint = Uri.parse('https://eu.i.posthog.com/i/v0/e/');

  @visibleForTesting
  static void resetAttemptForTest() => attemptTracker.reset();

  static bool validProjectToken(String token) => _tokenPattern.hasMatch(token);

  static String newPingId() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256)
        .toRadixString(16).padLeft(2, '0')).join();
  }

  static Map<String, Object> syntheticEvent({
    required String projectToken,
    required String pingId,
  }) {
    if (!validProjectToken(projectToken) || !_idPattern.hasMatch(pingId)) {
      throw const FormatException('Token di progetto o ID di test non valido');
    }
    return {
      'api_key': projectToken,
      'event': 'cm_lab_ping',
      'distinct_id': 'cm-ping-$pingId',
      'properties': <String, Object>{
        r'$process_person_profile': false,
        r'$geoip_disable': true,
        'ping_id': pingId,
        'schema_version': 1,
        'kind': 'manual_synthetic_connectivity',
      },
    };
  }

  /// No retry, no queue and no persistence. HTTP success does not prove the
  /// event is stored; check the matching ping_id in PostHog separately.
  static Future<int> sendOnce({required String pingId}) async {
    if (temporarilyDisabled) {
      throw StateError('PostHog sending temporarily disabled in this build');
    }
    if (!isConfigured) {
      throw StateError('Project ingestion token not configured');
    }
    final jsonBody = jsonEncode(
      syntheticEvent(projectToken: _buildToken, pingId: pingId),
    );
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(_endpoint).timeout(
        const Duration(seconds: 12),
      );
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.write(jsonBody);
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      final status = response.statusCode;
      await response.drain<void>().timeout(const Duration(seconds: 12));
      return status;
    } finally {
      client.close(force: true);
    }
  }
}
