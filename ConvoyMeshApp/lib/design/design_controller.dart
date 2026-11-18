import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'design_tokens.dart';

/// Holds the locally selected visual direction (a pure UI preference).
///
/// Default is [DesignDirection.classic], i.e. the original interface. The
/// value is stored only on the device via the already-used SharedPreferences
/// dependency; it is never recorded in diagnostics or sent anywhere.
class DesignDirectionController extends ChangeNotifier {
  DesignDirectionController._();

  @visibleForTesting
  DesignDirectionController.forTest([DesignDirection initial = DesignDirection.classic])
      : _direction = initial;

  static final instance = DesignDirectionController._();
  static const storageKey = 'design_studio.direction';

  DesignDirection _direction = DesignDirection.classic;
  DesignDirection get direction => _direction;
  bool get isClassic => _direction == DesignDirection.classic;

  /// Best-effort load; any storage error keeps the original interface.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(storageKey);
      final match = DesignDirection.values.where((d) => d.storageId == stored);
      if (match.isNotEmpty && match.first != _direction) {
        _direction = match.first;
        notifyListeners();
      }
    } catch (_) {
      // Keep classic: a UI preference must never block app start.
    }
  }

  Future<void> select(DesignDirection direction) async {
    if (direction == _direction) return;
    _direction = direction;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, direction.storageId);
    } catch (_) {
      // Selection still applies for this session.
    }
  }
}
