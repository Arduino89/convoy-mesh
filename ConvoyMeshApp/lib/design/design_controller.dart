import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'design_presets.dart';
import 'design_tokens.dart';
import 'outdoor_config.dart';

/// Holds the active UI mode (`Outdoor Premium` or `Originale LAB +15`) and the
/// fine-grained customisation settings for Outdoor Premium.
///
/// Stored strictly locally via `SharedPreferences`; never written into diagnostic
/// logs or transmitted remotely.
class DesignDirectionController extends ChangeNotifier {
  DesignDirectionController._()
      : _direction = defaultOutdoor
            ? DesignDirection.outdoorPremium
            : DesignDirection.classic,
        _config = OutdoorCustomConfig.defaults;

  @visibleForTesting
  DesignDirectionController.forTest([
    DesignDirection initial = DesignDirection.classic,
    OutdoorCustomConfig initialConfig = OutdoorCustomConfig.defaults,
  ])  : _direction = initial,
        _config = initialConfig;

  /// Set via `--dart-define=CONVOY_DEFAULT_OUTDOOR=true` on the Outdoor LAB
  /// private build so clean installs open directly in Outdoor Premium while
  /// retaining one-tap revert to Original (`LAB +15`).
  static const bool defaultOutdoor =
      bool.fromEnvironment('CONVOY_DEFAULT_OUTDOOR');

  static final instance = DesignDirectionController._();
  static const storageKey = 'design_studio.direction';
  static const configStorageKey = 'design_studio.outdoor_config';

  DesignDirection _direction;
  OutdoorCustomConfig _config;
  ConvoyDesignTokens? _cachedOutdoorTokens;
  int _mutationEpoch = 0;
  bool _loaded = false;
  String? _lastPersistenceError;
  Future<void>? _activeWrite;

  DesignDirection get direction => _direction;
  OutdoorCustomConfig get config => _config;
  bool get isClassic => _direction == DesignDirection.classic;
  bool get hasLoaded => _loaded;
  String? get lastPersistenceError => _lastPersistenceError;

  /// Cached tokens for Outdoor Premium; rebuilt only when [_config] changes.
  ConvoyDesignTokens get outdoorTokens =>
      _cachedOutdoorTokens ??= DesignPresets.buildOutdoor(_config);
  ConvoyDesignTokens? get activeTokens => isClassic ? null : outdoorTokens;

  Future<bool> _enqueuePersist(
    Future<void> Function(SharedPreferences prefs) write,
  ) {
    final prev = _activeWrite;
    late final Future<bool> current;
    Future<bool> run() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await write(prefs);
        _lastPersistenceError = null;
        return true;
      } catch (e) {
        _lastPersistenceError = e.toString();
        return false;
      } finally {
        if (identical(_activeWrite, current)) {
          _activeWrite = null;
        }
      }
    }

    current = prev == null ? run() : prev.then((_) => run());
    _activeWrite = current;
    return current;
  }

  /// Best-effort load; storage errors never block app startup, and a slow load
  /// can never overwrite a user selection made earlier during startup.
  Future<void> load() async {
    final startEpoch = _mutationEpoch;
    DesignDirection? loadedDirection;
    OutdoorCustomConfig? loadedConfig;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(storageKey);
      if (stored != null) {
        loadedDirection = stored == DesignDirection.classic.storageId
            ? DesignDirection.classic
            : DesignDirection.outdoorPremium;
      }

      final rawCfg = prefs.getString(configStorageKey);
      if (rawCfg != null && rawCfg.isNotEmpty) {
        final decoded = jsonDecode(rawCfg);
        if (decoded is Map<String, dynamic>) {
          loadedConfig = OutdoorCustomConfig.fromJson(decoded);
        }
      }
    } catch (_) {
      // Keep safe defaults.
    }
    _loaded = true;
    // Discard stale disk read if a user mutation occurred while load() was in flight.
    if (_mutationEpoch != startEpoch) return;
    var changed = false;
    if (loadedDirection != null && loadedDirection != _direction) {
      _direction = loadedDirection;
      changed = true;
    }
    if (loadedConfig != null && loadedConfig != _config) {
      _config = loadedConfig;
      _cachedOutdoorTokens = null;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  Future<bool> select(DesignDirection direction) async {
    if (direction == _direction) return true;
    _mutationEpoch++;
    _direction = direction;
    notifyListeners();
    return _enqueuePersist(
      (prefs) => prefs.setString(storageKey, direction.storageId),
    );
  }

  Future<bool> updateConfig(
    OutdoorCustomConfig next, {
    bool activateOutdoor = false,
  }) async {
    final switchMode =
        activateOutdoor && _direction != DesignDirection.outdoorPremium;
    if (next == _config && !switchMode) return true;
    _mutationEpoch++;
    _config = next;
    _cachedOutdoorTokens = null;
    if (switchMode) _direction = DesignDirection.outdoorPremium;
    notifyListeners();
    final encoded = jsonEncode(next.toJson());
    return _enqueuePersist((prefs) async {
      await prefs.setString(configStorageKey, encoded);
      if (switchMode) {
        await prefs.setString(
          storageKey,
          DesignDirection.outdoorPremium.storageId,
        );
      }
    });
  }

  /// Atomically updates both [direction] and [config] with a single
  /// notification and a single serialized persistence batch.
  Future<bool> applySelection(
    DesignDirection direction,
    OutdoorCustomConfig next,
  ) async {
    final dirChanged = direction != _direction;
    final cfgChanged = next != _config;
    if (!dirChanged && !cfgChanged) return true;
    _mutationEpoch++;
    _direction = direction;
    if (cfgChanged) {
      _config = next;
      _cachedOutdoorTokens = null;
    }
    notifyListeners();
    final encoded = cfgChanged ? jsonEncode(next.toJson()) : null;
    return _enqueuePersist((prefs) async {
      if (encoded != null) {
        await prefs.setString(configStorageKey, encoded);
      }
      if (dirChanged) {
        await prefs.setString(storageKey, direction.storageId);
      }
    });
  }

  Future<bool> resetConfig() => updateConfig(OutdoorCustomConfig.defaults);
}
