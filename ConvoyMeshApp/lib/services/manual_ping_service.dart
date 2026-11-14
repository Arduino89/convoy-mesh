import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Single explicit, synthetic connectivity probe. Never reads GPS, BLE, names,
/// diagnostic files, persistent identifiers or any other application state.
class ManualPingService {
  // Compile-time ingestion-only public project token, never tracked in git.
  static const String _buildToken =
      String.fromEnvironment('CONVOY_POSTHOG_PROJECT_TOKEN');
  static bool get isConfigured =>
      validProjectToken(_buildToken) && _buildToken != 'phc_synthetic_local_only';
  static final RegExp _tokenPattern = RegExp(r'^phc_[A-Za-z0-9_-]{16,200}$');
  static final RegExp _idPattern = RegExp(r'^[a-f0-9]{32}$');
  static final Uri _endpoint = Uri.parse('https://eu.i.posthog.com/i/v0/e/');

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
