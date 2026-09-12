/// One owner for NAME, POS and PING scheduling. Times are monotonic.
/// A name request is coalesced (not six future slots) and cannot starve POS.
enum BleTxKind { position, name, ping }

class BleTxScheduler {
  static const heartbeatEvery = Duration(seconds: 5);
  static const nameEvery = Duration(seconds: 30);
  static const minRefreshInterval = Duration(seconds: 1);

  Duration? _lastTx;
  Duration? _lastName;
  BleTxKind? _lastKind;
  bool _namePending = true;

  void requestName() => _namePending = true;

  BleTxKind? choose({
    required Duration now,
    required bool hasFreshPosition,
    bool refresh = false,
  }) {
    final elapsed = _lastTx == null ? null : now - _lastTx!;
    if (elapsed != null && elapsed <
        (refresh ? minRefreshInterval : heartbeatEvery)) return null;
    final nameDue = _namePending || _lastName == null || now - _lastName! >= nameEvery;
    // Even a flood of name requests must alternate with fresh position.
    if (hasFreshPosition && (_lastKind == BleTxKind.name || refresh)) {
      return BleTxKind.position;
    }
    if (nameDue) return BleTxKind.name;
    return hasFreshPosition ? BleTxKind.position : BleTxKind.ping;
  }

  /// Call only after the advertiser reports success. Failed attempts remain due.
  void didSend(BleTxKind kind, Duration now) {
    _lastTx = now;
    _lastKind = kind;
    if (kind == BleTxKind.name) {
      _lastName = now;
      _namePending = false;
    }
  }
}
