import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:convoy_mesh/ledger/ledger_foundation.dart';

LedgerPoint point(String origin, String incarnation, int id) => LedgerPoint(
      key: LedgerPointKey(
        stream: LedgerStreamId(originId: origin, incarnationId: incarnation),
        pointId: id,
      ),
      segmentId: id ~/ 5,
      timeOffsetMs: id * 5000,
      latE7: 450000000 + origin.codeUnitAt(0) * 10000 + id * 11,
      lonE7: 100000000 + incarnation.codeUnitAt(0) * 10000 + id * 7,
      accuracyDm: 50 + (id % 20),
      state: id % 3,
    );

List<LedgerPoint> canonicalFixture() {
  final result = <LedgerPoint>[];
  for (var author = 0; author < 6; author++) {
    final origin = String.fromCharCode(65 + author);
    for (var incarnation = 0; incarnation < 3; incarnation++) {
      for (var id = 0; id < 12; id++) {
        result.add(point(origin, '$origin-$incarnation', id));
      }
    }
  }
  result.sort((a, b) => a.key.compareTo(b.key));
  return result;
}

void main() {
  test('250 randomized relay/replay orders converge to the same union', () {
    final expected = canonicalFixture();
    for (var seed = 0; seed < 250; seed++) {
      final random = Random(seed);
      final delivery = List<LedgerPoint>.of(expected)..shuffle(random);
      final ledger = ReferenceLedger();

      var cursor = 0;
      while (cursor < delivery.length) {
        final width = min(delivery.length - cursor, 1 + random.nextInt(17));
        final batch = delivery.sublist(cursor, cursor + width);
        ledger.merge(batch);
        if (random.nextBool()) ledger.merge(batch); // lost ACK / relay replay analogue.
        cursor += width;
      }

      expect(ledger.points, expected, reason: 'seed=$seed');
      expect(ledger.conflicts, isEmpty, reason: 'seed=$seed');
    }
  });

  test('merge is associative/commutative for non-conflicting immutable records', () {
    final source = canonicalFixture();
    for (var seed = 0; seed < 150; seed++) {
      final random = Random(1000 + seed);
      final x = <LedgerPoint>[];
      final y = <LedgerPoint>[];
      final z = <LedgerPoint>[];
      for (final value in source) {
        final bucket = random.nextInt(3);
        if (bucket == 0) x.add(value);
        if (bucket == 1) y.add(value);
        if (bucket == 2) z.add(value);
        if (random.nextInt(5) == 0) {
          // A second relay can carry the same record in another set.
          [x, y, z][random.nextInt(3)].add(value);
        }
      }

      final xyz = ReferenceLedger()..merge(x)..merge(y)..merge(z);
      final zyx = ReferenceLedger()..merge(z)..merge(y)..merge(x);
      final grouped = ReferenceLedger()
        ..merge((ReferenceLedger()..merge(x)..merge(y)).points)
        ..merge(z);

      expect(zyx.points, xyz.points, reason: 'seed=$seed');
      expect(grouped.points, xyz.points, reason: 'seed=$seed');
      expect(xyz.conflicts, isEmpty, reason: 'seed=$seed');
    }
  });

  test('paged inventory preserves random sparse holes exactly', () {
    const stream = LedgerStreamId(originId: 'C', incarnationId: 'C-1');
    for (var seed = 0; seed < 200; seed++) {
      final random = Random(2000 + seed);
      final ids = <int>{};
      while (ids.length < 200) {
        ids.add(random.nextInt(5000));
      }
      final ledger = ReferenceLedger();
      for (final id in ids) {
        ledger.insert(point('C', 'C-1', id));
      }

      final reconstructed = <int>{};
      for (final page in ledger.inventoryPages(stream, pageSize: 256)) {
        expect(page.startPointId % 256, 0, reason: 'seed=$seed');
        for (final id in page.presentPointIds) {
          expect(id, inInclusiveRange(page.startPointId, page.startPointId + 255));
        }
        reconstructed.addAll(page.presentPointIds);
      }
      expect(reconstructed, ids, reason: 'seed=$seed');
    }
  });

  test('session fan-out cannot steal author turns while all authors have work', () {
    final queue = AuthorFirstFairQueue();

    // A deliberately opens far more sessions than anyone else.
    for (var session = 0; session < 100; session++) {
      queue.add(
        LedgerWorkItem(
          originId: 'A',
          incarnationId: 'A-$session',
          token: 'A-$session',
          costBytes: 100,
        ),
      );
    }
    // Nineteen other authors each have ten queued units.
    for (var author = 1; author < 20; author++) {
      for (var item = 0; item < 10; item++) {
        queue.add(
          LedgerWorkItem(
            originId: 'P$author',
            incarnationId: 'P$author-main',
            token: 'P$author-$item',
            costBytes: 100,
          ),
        );
      }
    }

    final counts = <String, int>{};
    for (var i = 0; i < 200; i++) {
      final next = queue.takeNext()!;
      counts[next.originId] = (counts[next.originId] ?? 0) + 1;
    }

    expect(counts.length, 20);
    for (final count in counts.values) {
      expect(count, 10);
    }
    expect(queue.length, 90); // Only A's excess sessions remain.
  });
}
