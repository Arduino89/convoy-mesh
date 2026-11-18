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
      : _direction =
            defaultOutdoor ? DesignDirection.outdoorPremium : DesignDirection.classic,
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

  DesignDirection get direction => _direction;
  OutdoorCustomConfig get config => _config;
  bool get isClassic => _direction == DesignDirection.classic;

  /// Effective tokens when Outdoor Premium is active (`null` in classic mode).
  ConvoyDesignTokens get outdoorTokens => DesignPresets.buildOutdoor(_config);
  ConvoyDesignTokens? get activeTokens => isClassic ? null : outdoorTokens;

  /// Best-effort load; storage errors never block app startup.
  Future<void> load() async {
    var changed = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(storageKey);
      if (stored != null) {
        final DesignDirection resolved;
        if (stored == DesignDirection.classic.storageId) {
          resolved = DesignDirection.classic;
        } else {
          // Includes 'outdoorPremium' and any archived prior preview IDs.
          resolved = DesignDirection.outdoorPremium;
        }
        if (resolved != _direction) {
          _direction = resolved;
          changed = true;
        }
      }

      final rawCfg = prefs.getString(configStorageKey);
      if (rawCfg != null && rawCfg.isNotEmpty) {
        final decoded = jsonDecode(rawCfg);
        if (decoded is Map<String, dynamic>) {
          final parsed = OutdoorCustomConfig.fromJson(decoded);
          if (parsed != _config) {
            _config = parsed;
            changed = true;
          }
        }
      }
    } catch (_) {
      // Keep safe defaults.
    }
    if (changed) notifyListeners();
  }

  Future<void> select(DesignDirection direction) async {
    if (direction == _direction) return;
    _direction = direction;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, direction.storageId);
    } catch (_) {
      // Selection still applies in-memory for this session.
    }
  }

  Future<void> updateConfig(
    OutdoorCustomConfig next, {
    bool activateOutdoor = false,
  }) async {
    final switchMode =
        activateOutdoor && _direction != DesignDirection.outdoorPremium;
    if (next == _config && !switchMode) return;
    _config = next;
    if (switchMode) _direction = DesignDirection.outdoorPremium;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(configStorageKey, jsonEncode(next.toJson()));
      if (switchMode) {
        await prefs.setString(storageKey, DesignDirection.outdoorPremium.storageId);
      }
    } catch (_) {
      // Config remains active in-memory.
    }
  }

  Future<void> resetConfig() => updateConfig(OutdoorCustomConfig.defaults);
}
