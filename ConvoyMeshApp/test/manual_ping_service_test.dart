import 'package:flutter_test/flutter_test.dart';
import 'package:convoy_mesh/services/manual_ping_service.dart';

void main() {
  const projectToken = 'phc_1234567890abcdefghijklmn';
  const pingId = '0123456789abcdef0123456789abcdef';

  test('one-shot payload is synthetic, anonymous and precisely allowlisted', () {
    final data = ManualPingService.syntheticEvent(
      projectToken: projectToken, pingId: pingId,
    );
    expect(data.keys.toSet(), {'api_key', 'event', 'distinct_id', 'properties'});
    expect(data['event'], 'cm_lab_ping');
    expect(data['distinct_id'], 'cm-ping-$pingId');
    final properties = data['properties'] as Map<String, Object>;
    expect(properties.keys.toSet(), {
      r'$process_person_profile', 'ping_id', 'schema_version', 'kind'
    });
    expect(properties[r'$process_person_profile'], false);
    expect(properties['ping_id'], pingId);
  });

  test('reject non-project token and invalid IDs before any network call', () {
    expect(ManualPingService.validProjectToken(projectToken), isTrue);
    for (final invalid in ['', 'sk-test', 'phx_test', 'phc_123', 'phc_12345!']) {
      expect(ManualPingService.validProjectToken(invalid), isFalse);
      expect(() => ManualPingService.syntheticEvent(
        projectToken: invalid, pingId: pingId,
      ), throwsFormatException);
    }
    expect(() => ManualPingService.syntheticEvent(
      projectToken: projectToken, pingId: 'too-short',
    ), throwsFormatException);
  });

  test('random probe IDs are non-device-derived and well formed', () {
    final ids = List.generate(10, (_) => ManualPingService.newPingId());
    expect(ids.toSet().length, ids.length);
    for (final id in ids) {
      expect(RegExp(r'^[a-f0-9]{32}$').hasMatch(id), isTrue);
    }
  });
}
