import 'package:flutter_test/flutter_test.dart';
import 'package:convoy_mesh/ledger/ledger_foundation.dart';

LedgerPoint p(
  String origin,
  String incarnation,
  int id, {
  int segment = 0,
  int lat = 450000000,
  int lon = 100000000,
}) =>
    LedgerPoint(
      key: LedgerPointKey(
        stream: LedgerStreamId(originId: origin, incarnationId: incarnation),
        pointId: id,
      ),
      segmentId: segment,
      timeOffsetMs: id * 5000,
      latE7: lat + id,
      lonE7: lon + id,
      accuracyDm: 80,
      state: 0,
    );

void main() {
  group('immutable additive merge', () {
    test('duplicate relay delivery is idempotent', () {
      final ledger = ReferenceLedger();
      expect(ledger.insert(p('C', 'c1', 7)), LedgerInsertStatus.inserted);
      expect(ledger.insert(p('C', 'c1', 7)), LedgerInsertStatus.duplicate);
      expect(ledger.length, 1);
      expect(ledger.conflicts, isEmpty);
    });

    test('same key with different content is explicit conflict, never overwrite', () {
      final ledger = ReferenceLedger();
      final original = p('C', 'c1', 7, lat: 450000000);
      final conflicting = p('C', 'c1', 7, lat: 460000000);
      ledger.insert(original);
      expect(ledger.insert(conflicting), LedgerInsertStatus.conflict);
      expect(ledger.pointFor(original.key), original);
      expect(ledger.conflicts, hasLength(1));
    });

    test('partial remote subset cannot delete local points', () {
      final ledger = ReferenceLedger()
        ..merge([p('C', 'c1', 1), p('C', 'c1', 2), p('C', 'c1', 3)]);
      ledger.merge([p('C', 'c1', 3)]);
      expect(
        ledger.pointIdsForStream(
          const LedgerStreamId(originId: 'C', incarnationId: 'c1'),
        ),
        {1, 2, 3},
      );
    });

    test('same point id in a new incarnation is a different record', () {
      final ledger = ReferenceLedger()
        ..insert(p('C', 'c1', 1))
        ..insert(p('C', 'c2', 1));
      expect(ledger.length, 2);
    });

    test('segment identity survives relay merge', () {
      final a = ReferenceLedger();
      final b = ReferenceLedger()..insert(p('C', 'c1', 9, segment: 4));
      a.merge(b.points);
      expect(a.points.single.segmentId, 4);
    });
  });

  group('A/B/C/D store-carry-forward semantics', () {
    test('B carries C to A, then C returns and receives B via A', () {
      final a = ReferenceLedger()..merge([p('A', 'a1', 0)]);
      final b = ReferenceLedger()..merge([p('B', 'b1', 0)]);
      final c = ReferenceLedger()..merge([p('C', 'c1', 0)]);

      // B and C leave A and exchange new author-owned observations.
      b.merge([p('B', 'b1', 1), p('C', 'c1', 0), p('C', 'c1', 1)]);
      c.merge([p('C', 'c1', 1), p('B', 'b1', 0), p('B', 'b1', 1)]);

      // B returns to A while C is absent. C-authored points remain C-authored.
      a.merge(b.points);
      expect(a.pointsForOrigin('C').map((e) => e.key.pointId).toSet(), {0, 1});
      expect(a.pointsForOrigin('B').map((e) => e.key.pointId).toSet(), {0, 1});

      // C later returns with a new C point and without B physically present.
      c.insert(p('C', 'c1', 2));
      a.merge(c.points);
      c.merge(a.points);

      expect(a.pointsForOrigin('C').map((e) => e.key.pointId).toSet(), {0, 1, 2});
      expect(c.pointsForOrigin('B').map((e) => e.key.pointId).toSet(), {0, 1});
      expect(a.length, c.length);

      // New D can receive the accumulated union from A without changing authorship.
      final d = ReferenceLedger()..merge(a.points);
      expect(d.length, a.length);
      expect(d.pointsForOrigin('B'), hasLength(2));
      expect(d.pointsForOrigin('C'), hasLength(3));
    });

    test('equivalent encounter orders converge to the same logical union', () {
      final source = [
        p('A', 'a1', 0),
        p('B', 'b1', 0),
        p('B', 'b1', 1),
        p('C', 'c1', 0),
        p('C', 'c1', 1),
      ];
      final first = ReferenceLedger()..merge(source);
      final second = ReferenceLedger()..merge(source.reversed);
      expect(second.points, first.points);
    });
  });

  group('exact paged inventory', () {
    test('holes remain explicit and upper point id does not imply completeness', () {
      const stream = LedgerStreamId(originId: 'C', incarnationId: 'c1');
      final ledger = ReferenceLedger()
        ..merge([
          p('C', 'c1', 1),
          p('C', 'c1', 2),
          p('C', 'c1', 200),
          p('C', 'c1', 511),
        ]);
      final pages = ledger.inventoryPages(stream, pageSize: 256);
      expect(pages, hasLength(2));
      expect(pages[0].presentPointIds, {1, 2, 200});
      expect(pages[1].presentPointIds, {511});
    });

    test('missing plan asks only for remote-present local-missing ids', () {
      const stream = LedgerStreamId(originId: 'C', incarnationId: 'c1');
      final local = ReferenceLedger()..merge([p('C', 'c1', 1), p('C', 'c1', 3)]);
      final remote = LedgerInventoryPage(
        stream: stream,
        startPointId: 0,
        pageSize: 256,
        presentPointIds: const {1, 2, 3, 9},
      );
      expect(local.missingFromRemotePage(remote), {2, 9});
      expect(local.pointIdsForStream(stream), {1, 3});
    });
  });

  group('author-first fairness', () {
    test('many sessions from one author do not buy extra author turns', () {
      final queue = AuthorFirstFairQueue();
      for (var s = 0; s < 10; s++) {
        queue.add(
          LedgerWorkItem(
            originId: 'A',
            incarnationId: 'a$s',
            token: 'A$s',
            costBytes: 100,
          ),
        );
      }
      for (var i = 0; i < 9; i++) {
        queue.add(
          LedgerWorkItem(
            originId: 'P$i',
            incarnationId: 'p$i',
            token: 'P$i',
            costBytes: 100,
          ),
        );
      }

      final firstTenAuthors = <String>[];
      for (var i = 0; i < 10; i++) {
        firstTenAuthors.add(queue.takeNext()!.originId);
      }
      expect(firstTenAuthors.toSet(), hasLength(10));
      expect(firstTenAuthors.where((id) => id == 'A'), hasLength(1));
    });
  });
}
