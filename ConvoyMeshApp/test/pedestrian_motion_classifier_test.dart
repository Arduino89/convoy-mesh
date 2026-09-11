import 'package:convoy_mesh/location/pedestrian_motion_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PedestrianMotionUpdate feed(
    PedestrianMotionClassifier classifier,
    double magnitude,
    int milliseconds,
  ) =>
      classifier.addSample(magnitude, Duration(milliseconds: milliseconds));

  test('stationary sensor noise never becomes walking', () {
    final classifier = PedestrianMotionClassifier();
    for (var ms = 0; ms <= 30000; ms += 100) {
      final noise = switch ((ms ~/ 100) % 4) {
        0 => 0.04,
        1 => 0.09,
        2 => 0.13,
        _ => 0.07,
      };
      final update = feed(classifier, noise, ms);
      expect(update.moving, isFalse, reason: 'ms=$ms score=${update.score}');
    }
  });

  test('slow but sustained motion is detected without waiting for strong threshold', () {
    final classifier = PedestrianMotionClassifier();
    PedestrianMotionUpdate? update;
    for (var ms = 0; ms <= 6000; ms += 100) {
      update = feed(classifier, 0.36, ms);
    }
    expect(update!.moving, isTrue);
    expect(update.score, lessThan(PedestrianMotionClassifier.strongMoveThreshold));
  });

  test('brief low-level handling does not masquerade as slow walking', () {
    final classifier = PedestrianMotionClassifier();
    for (var ms = 0; ms <= 2200; ms += 100) {
      expect(feed(classifier, 0.36, ms).moving, isFalse);
    }
    for (var ms = 2300; ms <= 8000; ms += 100) {
      expect(feed(classifier, 0.05, ms).moving, isFalse);
    }
  });

  test('strong walking enters quickly', () {
    final classifier = PedestrianMotionClassifier();
    PedestrianMotionUpdate? update;
    for (var ms = 0; ms <= 1600; ms += 100) {
      update = feed(classifier, 0.95, ms);
    }
    expect(update!.moving, isTrue);
  });

  test('short quiet dips do not flap a moving phone back to still', () {
    final classifier = PedestrianMotionClassifier();
    for (var ms = 0; ms <= 2000; ms += 100) {
      feed(classifier, 0.95, ms);
    }
    expect(classifier.moving, isTrue);

    for (var ms = 2100; ms <= 5200; ms += 100) {
      final update = feed(classifier, 0.02, ms);
      expect(update.moving, isTrue, reason: 'quiet dip ms=$ms');
    }
  });

  test('sustained quiet eventually returns to still', () {
    final classifier = PedestrianMotionClassifier();
    for (var ms = 0; ms <= 2000; ms += 100) {
      feed(classifier, 0.95, ms);
    }
    expect(classifier.moving, isTrue);

    PedestrianMotionUpdate? update;
    for (var ms = 2100; ms <= 10000; ms += 100) {
      update = feed(classifier, 0.01, ms);
    }
    expect(update!.moving, isFalse);
  });

  test('reliability expires when samples stop arriving', () {
    final classifier = PedestrianMotionClassifier();
    for (var ms = 0; ms <= 1000; ms += 100) {
      feed(classifier, 0.1, ms);
    }
    expect(classifier.isReliableAt(const Duration(seconds: 2)), isTrue);
    expect(classifier.isReliableAt(const Duration(seconds: 5)), isFalse);
  });
}
