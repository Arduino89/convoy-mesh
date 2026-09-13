import 'dart:collection';

/// Transport-independent reference semantics for the future Convoy ledger.
///
/// This file deliberately does not choose BLE transport, persistence engine,
/// byte layout, authentication scheme, retention duration, or radio scheduling.
/// It captures only merge/identity/inventory/fairness properties that should
/// remain true regardless of those later choices.
class LedgerStreamId implements Comparable<LedgerStreamId> {
  const LedgerStreamId({required this.originId, required this.incarnationId});

  final String originId;
  final String incarnationId;

  @override
  int compareTo(LedgerStreamId other) {
    final byOrigin = originId.compareTo(other.originId);
    if (byOrigin != 0) return byOrigin;
    return incarnationId.compareTo(other.incarnationId);
  }

  @override
  bool operator ==(Object other) =>
      other is LedgerStreamId &&
      originId == other.originId &&
      incarnationId == other.incarnationId;

  @override
  int get hashCode => Object.hash(originId, incarnationId);

  @override
  String toString() => '$originId/$incarnationId';
}

class LedgerPointKey implements Comparable<LedgerPointKey> {
  const LedgerPointKey({required this.stream, required this.pointId});

  final LedgerStreamId stream;
  final int pointId;

  @override
  int compareTo(LedgerPointKey other) {
    final byStream = stream.compareTo(other.stream);
    if (byStream != 0) return byStream;
    return pointId.compareTo(other.pointId);
  }

  @override
  bool operator ==(Object other) =>
      other is LedgerPointKey && stream == other.stream && pointId == other.pointId;

  @override
  int get hashCode => Object.hash(stream, pointId);

  @override
  String toString() => '$stream#$pointId';
}

class LedgerPoint {
  const LedgerPoint({
    required this.key,
    required this.segmentId,
    required this.timeOffsetMs,
    required this.latE7,
    required this.lonE7,
    required this.accuracyDm,
    required this.state,
  });

  final LedgerPointKey key;
  final int segmentId;
  final int timeOffsetMs;
  final int latE7;
  final int lonE7;
  final int accuracyDm;
  final int state;

  String get originId => key.stream.originId;
  LedgerStreamId get stream => key.stream;

  bool sameContentAs(LedgerPoint other) =>
      key == other.key &&
      segmentId == other.segmentId &&
      timeOffsetMs == other.timeOffsetMs &&
      latE7 == other.latE7 &&
      lonE7 == other.lonE7 &&
      accuracyDm == other.accuracyDm &&
      state == other.state;

  @override
  bool operator ==(Object other) => other is LedgerPoint && sameContentAs(other);

  @override
  int get hashCode => Object.hash(
        key,
        segmentId,
        timeOffsetMs,
        latE7,
        lonE7,
        accuracyDm,
        state,
      );
}

enum LedgerInsertStatus { inserted, duplicate, conflict }

class LedgerConflict {
  const LedgerConflict({required this.existing, required this.incoming});

  final LedgerPoint existing;
  final LedgerPoint incoming;
}

class LedgerMergeReport {
  const LedgerMergeReport({
    required this.inserted,
    required this.duplicates,
    required this.conflicts,
  });

  final int inserted;
  final int duplicates;
  final List<LedgerConflict> conflicts;

  bool get hasConflicts => conflicts.isNotEmpty;
}

/// Exact possession for one fixed point-id interval of one stream.
class LedgerInventoryPage {
  LedgerInventoryPage({
    required this.stream,
    required this.startPointId,
    required this.pageSize,
    required Iterable<int> presentPointIds,
  }) : presentPointIds = Set<int>.unmodifiable(presentPointIds) {
    if (startPointId < 0) throw ArgumentError.value(startPointId, 'startPointId');
    if (pageSize <= 0) throw ArgumentError.value(pageSize, 'pageSize');
    for (final id in this.presentPointIds) {
      if (id < startPointId || id >= startPointId + pageSize) {
        throw ArgumentError('Point $id outside inventory page');
      }
    }
  }

  final LedgerStreamId stream;
  final int startPointId;
  final int pageSize;
  final Set<int> presentPointIds;
}

/// In-memory oracle for merge semantics. This is intentionally not the future
/// production persistence layer: SQLite/other durability must be benchmarked on
/// the real Android targets before it is frozen.
class ReferenceLedger {
  final Map<LedgerPointKey, LedgerPoint> _points = <LedgerPointKey, LedgerPoint>{};
  final List<LedgerConflict> _conflicts = <LedgerConflict>[];

  int get length => _points.length;
  bool get isEmpty => _points.isEmpty;
  List<LedgerConflict> get conflicts => List<LedgerConflict>.unmodifiable(_conflicts);

  List<LedgerPoint> get points {
    final result = _points.values.toList(growable: false);
    result.sort((a, b) => a.key.compareTo(b.key));
    return List<LedgerPoint>.unmodifiable(result);
  }

  bool containsKey(LedgerPointKey key) => _points.containsKey(key);
  LedgerPoint? pointFor(LedgerPointKey key) => _points[key];

  LedgerInsertStatus insert(LedgerPoint point) {
    final existing = _points[point.key];
    if (existing == null) {
      _points[point.key] = point;
      return LedgerInsertStatus.inserted;
    }
    if (existing.sameContentAs(point)) return LedgerInsertStatus.duplicate;
    _conflicts.add(LedgerConflict(existing: existing, incoming: point));
    return LedgerInsertStatus.conflict;
  }

  /// Additive merge only. A partial remote snapshot can never delete local data.
  LedgerMergeReport merge(Iterable<LedgerPoint> incoming) {
    var inserted = 0;
    var duplicates = 0;
    final conflicts = <LedgerConflict>[];
    for (final point in incoming) {
      final beforeConflicts = _conflicts.length;
      switch (insert(point)) {
        case LedgerInsertStatus.inserted:
          inserted++;
          break;
        case LedgerInsertStatus.duplicate:
          duplicates++;
          break;
        case LedgerInsertStatus.conflict:
          if (_conflicts.length == beforeConflicts + 1) {
            conflicts.add(_conflicts.last);
          }
      }
    }
    return LedgerMergeReport(
      inserted: inserted,
      duplicates: duplicates,
      conflicts: List<LedgerConflict>.unmodifiable(conflicts),
    );
  }

  List<LedgerPoint> pointsForOrigin(String originId) => List<LedgerPoint>.unmodifiable(
        points.where((point) => point.originId == originId),
      );

  List<LedgerPoint> pointsForStream(LedgerStreamId stream) => List<LedgerPoint>.unmodifiable(
        points.where((point) => point.stream == stream),
      );

  Set<int> pointIdsForStream(LedgerStreamId stream) => Set<int>.unmodifiable(
        _points.keys.where((key) => key.stream == stream).map((key) => key.pointId),
      );

  List<LedgerInventoryPage> inventoryPages(
    LedgerStreamId stream, {
    int pageSize = 256,
  }) {
    if (pageSize <= 0) throw ArgumentError.value(pageSize, 'pageSize');
    final ids = pointIdsForStream(stream).toList()..sort();
    if (ids.isEmpty) return const <LedgerInventoryPage>[];
    final grouped = <int, List<int>>{};
    for (final id in ids) {
      if (id < 0) throw StateError('Negative point id cannot be inventoried');
      final start = (id ~/ pageSize) * pageSize;
      grouped.putIfAbsent(start, () => <int>[]).add(id);
    }
    final starts = grouped.keys.toList()..sort();
    return List<LedgerInventoryPage>.unmodifiable(
      starts.map(
        (start) => LedgerInventoryPage(
          stream: stream,
          startPointId: start,
          pageSize: pageSize,
          presentPointIds: grouped[start]!,
        ),
      ),
    );
  }

  /// Exact delta for one received inventory page. Absence in [remotePage] never
  /// deletes local records; it only means the remote peer did not advertise
  /// those IDs in this page/snapshot.
  Set<int> missingFromRemotePage(LedgerInventoryPage remotePage) {
    final local = pointIdsForStream(remotePage.stream);
    return Set<int>.unmodifiable(remotePage.presentPointIds.difference(local));
  }
}

class LedgerWorkItem {
  const LedgerWorkItem({
    required this.originId,
    required this.incarnationId,
    required this.token,
    required this.costBytes,
  });

  final String originId;
  final String incarnationId;
  final String token;
  final int costBytes;
}

/// Reference fairness rule: authors rotate first; sessions/incarnations rotate
/// only inside their author. This prevents one author from gaining extra turns
/// merely by creating many sessions. Production scheduling should additionally
/// use byte deficits/aging, but must preserve this author-first property.
class AuthorFirstFairQueue {
  final Map<String, Map<String, Queue<LedgerWorkItem>>> _queues =
      <String, Map<String, Queue<LedgerWorkItem>>>{};
  final Queue<String> _authors = Queue<String>();
  final Set<String> _authorsQueued = <String>{};
  final Map<String, Queue<String>> _sessions = <String, Queue<String>>{};
  final Map<String, Set<String>> _sessionsQueued = <String, Set<String>>{};
  var _length = 0;

  int get length => _length;
  bool get isEmpty => _length == 0;

  void add(LedgerWorkItem item) {
    if (item.costBytes <= 0) throw ArgumentError.value(item.costBytes, 'costBytes');
    final bySession = _queues.putIfAbsent(
      item.originId,
      () => <String, Queue<LedgerWorkItem>>{},
    );
    final queue = bySession.putIfAbsent(item.incarnationId, () => Queue<LedgerWorkItem>());
    queue.addLast(item);
    _length++;

    final sessions = _sessions.putIfAbsent(item.originId, () => Queue<String>());
    final sessionSet = _sessionsQueued.putIfAbsent(item.originId, () => <String>{});
    if (sessionSet.add(item.incarnationId)) sessions.addLast(item.incarnationId);
    if (_authorsQueued.add(item.originId)) _authors.addLast(item.originId);
  }

  LedgerWorkItem? takeNext() {
    if (_length == 0) return null;
    final authorAttempts = _authors.length;
    for (var attempt = 0; attempt < authorAttempts; attempt++) {
      final author = _authors.removeFirst();
      _authorsQueued.remove(author);
      final sessions = _sessions[author];
      final bySession = _queues[author];
      if (sessions == null || bySession == null) continue;

      LedgerWorkItem? selected;
      final sessionAttempts = sessions.length;
      for (var s = 0; s < sessionAttempts; s++) {
        final session = sessions.removeFirst();
        _sessionsQueued[author]?.remove(session);
        final queue = bySession[session];
        if (queue == null || queue.isEmpty) {
          bySession.remove(session);
          continue;
        }
        selected = queue.removeFirst();
        _length--;
        if (queue.isNotEmpty) {
          sessions.addLast(session);
          _sessionsQueued[author]?.add(session);
        } else {
          bySession.remove(session);
        }
        break;
      }

      if (bySession.isNotEmpty) {
        _authors.addLast(author);
        _authorsQueued.add(author);
      } else {
        _queues.remove(author);
        _sessions.remove(author);
        _sessionsQueued.remove(author);
      }
      if (selected != null) return selected;
    }
    return null;
  }
}
