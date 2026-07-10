import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

class DiagnosticRecorder extends ChangeNotifier {
  DiagnosticRecorder._();

  static final DiagnosticRecorder instance = DiagnosticRecorder._();

  static const Duration maxDuration = Duration(minutes: 4);
  static const int maxEvents = 20000;

  final List<String> _lines = <String>[];

  Stopwatch? _stopwatch;
  Timer? _limitTimer;
  Timer? _uiTimer;

  bool _active = false;
  DateTime? _startedAtUtc;
  String? _sessionId;
  int? _deviceId;
  String? _deviceName;

  String? _lastContent;
  String? _lastFileName;
  DateTime? _lastFinishedAtUtc;
  String? _lastStopReason;
  int _droppedEvents = 0;

  bool get isActive => _active;
  DateTime? get startedAtUtc => _startedAtUtc;
  String? get sessionId => _sessionId;
  int get eventCount => _lines.length;
  int get droppedEvents => _droppedEvents;
  Duration get elapsed => _stopwatch?.elapsed ?? Duration.zero;
  Duration get remaining {
    final left = maxDuration - elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  bool get hasExport => _lastContent != null && _lastFileName != null;
  String? get lastFileName => _lastFileName;
  String? get lastContent => _lastContent;
  DateTime? get lastFinishedAtUtc => _lastFinishedAtUtc;
  String? get lastStopReason => _lastStopReason;

  void start({
    required int deviceId,
    required String deviceName,
  }) {
    if (_active) {
      stop(reason: 'restart');
    }

    _lines.clear();
    _droppedEvents = 0;
    _lastContent = null;
    _lastFileName = null;
    _lastFinishedAtUtc = null;
    _lastStopReason = null;

    _deviceId = deviceId;
    _deviceName = _cleanName(deviceName);
    _startedAtUtc = DateTime.now().toUtc();
    _sessionId = _buildSessionId(_startedAtUtc!, deviceId);
    _stopwatch = Stopwatch()..start();
    _active = true;

    _append(
      category: 'session',
      event: 'start',
      data: <String, Object?>{
        'schema_version': 1,
        'app_version': '1.0.0+1',
        'device_id': deviceId,
        'device_name': _deviceName,
        'max_duration_ms': maxDuration.inMilliseconds,
        'timezone_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
      },
    );

    _limitTimer?.cancel();
    _limitTimer = Timer(maxDuration, () {
      stop(reason: 'auto_limit_4m');
    });

    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_active) notifyListeners();
    });

    notifyListeners();
  }

  void stop({String reason = 'manual'}) {
    if (!_active) return;

    _append(
      category: 'session',
      event: 'stop',
      data: <String, Object?>{
        'reason': reason,
        'events': _lines.length + 1,
        'dropped_events': _droppedEvents,
      },
    );

    _active = false;
    _stopwatch?.stop();
    _limitTimer?.cancel();
    _uiTimer?.cancel();
    _limitTimer = null;
    _uiTimer = null;

    _lastFinishedAtUtc = DateTime.now().toUtc();
    _lastStopReason = reason;
    _lastContent = '${_lines.join('\n')}\n';
    _lastFileName = _buildFileName(
      deviceName: _deviceName ?? 'device',
      startedAtUtc: _startedAtUtc ?? _lastFinishedAtUtc!,
      deviceId: _deviceId ?? 0,
    );

    notifyListeners();
  }

  void record(
    String category,
    String event, {
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    if (!_active) return;
    _append(category: category, event: event, data: data);
  }

  void addMarker(String note) {
    final cleaned = note.trim();
    if (!_active || cleaned.isEmpty) return;
    _append(
      category: 'user',
      event: 'marker',
      data: <String, Object?>{'note': cleaned},
    );
    notifyListeners();
  }

  Future<ShareResult?> shareLast() async {
    final content = _lastContent;
    final fileName = _lastFileName;
    if (content == null || fileName == null) return null;

    final file = XFile.fromData(
      Uint8List.fromList(utf8.encode(content)),
      mimeType: 'application/x-ndjson',
    );

    return SharePlus.instance.share(
      ShareParams(
        title: 'Condividi log Convoy Mesh',
        subject: 'Log diagnostico Convoy Mesh',
        text: 'Sessione diagnostica Convoy Mesh ${_sessionId ?? ''}',
        files: <XFile>[file],
        fileNameOverrides: <String>[fileName],
      ),
    );
  }

  void _append({
    required String category,
    required String event,
    required Map<String, Object?> data,
  }) {
    if (_lines.length >= maxEvents) {
      _droppedEvents++;
      return;
    }

    final nowUtc = DateTime.now().toUtc();
    final line = <String, Object?>{
      'ts_utc': nowUtc.toIso8601String(),
      'elapsed_ms': _stopwatch?.elapsedMilliseconds ?? 0,
      'session_id': _sessionId,
      'device_id': _deviceId,
      'device_name': _deviceName,
      'category': category,
      'event': event,
      'data': data,
    };

    _lines.add(jsonEncode(line));
  }

  static String formatDuration(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  static String _buildSessionId(DateTime utc, int deviceId) {
    return 'CM-${_compactUtc(utc)}-${deviceId.toRadixString(16).toUpperCase()}';
  }

  static String _buildFileName({
    required String deviceName,
    required DateTime startedAtUtc,
    required int deviceId,
  }) {
    final safeName = _cleanName(deviceName).replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return 'convoy-test-${safeName.isEmpty ? 'device' : safeName}-${deviceId.toRadixString(16).toUpperCase()}-${_compactUtc(startedAtUtc)}.jsonl';
  }

  static String _compactUtc(DateTime utc) {
    final value = utc.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}T${two(value.hour)}${two(value.minute)}${two(value.second)}Z';
  }

  static String _cleanName(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'device' : trimmed;
  }
}
