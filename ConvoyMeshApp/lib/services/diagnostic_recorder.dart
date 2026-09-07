import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Four-minute opt-in capture. One-second disk buffer; no automatic uploading.
/// A killed process may lose the last unflushed second, not the entire session.
class DiagnosticRecorder extends ChangeNotifier {
  DiagnosticRecorder._();
  @visibleForTesting
  DiagnosticRecorder.forTest();
  static final instance = DiagnosticRecorder._();
  static const maxDuration = Duration(minutes: 4);
  static const maxEvents = 20000;
  static const buildCommit = String.fromEnvironment('BUILD_COMMIT', defaultValue: 'local-unverified');
  final List<String> _lines = [], _pending = [];
  Directory? _directory;
  File? _file;
  Future<void> _writes = Future.value();
  String? storageError;
  bool get isPersistent => _directory != null && storageError == null;
  Stopwatch? _stopwatch;
  Timer? _limitTimer, _uiTimer;
  bool _active = false;
  DateTime? _startedAtUtc, _lastFinishedAtUtc;
  String? _sessionId, _deviceName, _lastContent, _lastFileName, _lastStopReason;
  int? _deviceId;
  int _droppedEvents = 0;
  bool get isActive => _active;
  DateTime? get startedAtUtc => _startedAtUtc;
  String? get sessionId => _sessionId;
  int get eventCount => _lines.length;
  int get droppedEvents => _droppedEvents;
  Duration get elapsed => _stopwatch?.elapsed ?? Duration.zero;
  Duration get remaining => elapsed >= maxDuration ? Duration.zero : maxDuration - elapsed;
  bool get hasExport => _lastContent != null && _lastFileName != null;
  String? get lastFileName => _lastFileName;
  String? get lastContent => _lastContent;
  DateTime? get lastFinishedAtUtc => _lastFinishedAtUtc;
  String? get lastStopReason => _lastStopReason;

  Future<void> initialize({Directory? directory}) async {
    if (_active) return;
    try {
      final path = directory?.path ?? await const MethodChannel('convoy_mesh/system')
          .invokeMethod<String>('getDiagnosticDirectory');
      if (path == null) throw const FileSystemException('Diagnostic directory unavailable');
      _directory = await Directory(path).create(recursive: true);
      storageError = null;
      final files = (await _directory!.list().toList()).whereType<File>()
          .where((f) => f.path.split(Platform.pathSeparator).last.startsWith('convoy-test-') && f.path.endsWith('.jsonl')).toList();
      files.sort((a, b) => a.path.compareTo(b.path));
      if (files.isNotEmpty && !hasExport) {
        final f = files.last;
        if (await f.length() <= 16 * 1024 * 1024) {
          _lastContent = await f.readAsString();
          _lastFileName = f.path.split(Platform.pathSeparator).last;
          _lastStopReason = 'recovered_file_check_session_stop';
          _file = f;
        }
      }
    } catch (e) { storageError = e.toString(); }
    notifyListeners();
  }
  void start({required int deviceId, required String deviceName}) {
    if (_active || deviceId <= 0) return;
    _lines.clear(); _pending.clear(); _droppedEvents = 0;
    _lastContent = null; _lastFinishedAtUtc = null; _lastStopReason = null;
    _deviceId = deviceId;
    _deviceName = deviceName.trim().isEmpty ? 'device' : deviceName.trim();
    _startedAtUtc = DateTime.now().toUtc();
    final stamp = _startedAtUtc!.toIso8601String().replaceAll(RegExp(r'[^0-9TZ]'), '');
    _sessionId = 'CM-$stamp-${deviceId.toRadixString(16)}';
    final safeName = _deviceName!.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    _lastFileName = 'convoy-test-$stamp-$deviceId-$safeName.jsonl';
    _file = _directory == null ? null : File('${_directory!.path}/$_lastFileName');
    _stopwatch = Stopwatch()..start();
    _active = true;
    _append('session', 'start', {
      'schema_version': 2, 'app_version': '0.7.0+7', 'build_commit': buildCommit,
      'max_duration_ms': maxDuration.inMilliseconds, 'disk_buffer_max_ms': 1000,
      'persistent_storage': isPersistent,
      'timezone_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
    });
    unawaited(flush());
    _limitTimer = Timer(maxDuration, () => stop(reason: 'auto_limit_4m'));
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (elapsed >= maxDuration) { stop(reason: 'auto_limit_4m'); return; }
      unawaited(flush());
      if (_active) notifyListeners();
    });
    notifyListeners();
  }
  void stop({String reason = 'manual'}) {
    if (!_active) return;
    _append('session', 'stop', {'reason': reason, 'events': _lines.length + 1,
      'dropped_events': _droppedEvents, 'storage_error': storageError}, terminal: true);
    _active = false; _stopwatch?.stop();
    _limitTimer?.cancel(); _uiTimer?.cancel(); _limitTimer = null; _uiTimer = null;
    _lastFinishedAtUtc = DateTime.now().toUtc(); _lastStopReason = reason;
    _lastContent = '${_lines.join('\n')}\n';
    unawaited(flush());
    notifyListeners();
  }
  void record(String category, String event, {Map<String, Object?> data = const {}}) {
    if (!_active) return;
    if (elapsed >= maxDuration) { stop(reason: 'auto_limit_4m'); return; }
    _append(category, event, data);
  }
  void addMarker(String note) {
    final cleaned = note.trim();
    if (!_active || cleaned.isEmpty) return;
    record('user', 'marker', data: {'note': cleaned});
    unawaited(flush()); notifyListeners();
  }
  Future<void> flush() {
    final file = _file;
    if (file == null || _pending.isEmpty) return _writes;
    final batch = '${_pending.join('\n')}\n';
    _pending.clear();
    _writes = _writes.then((_) async {
      try { await file.writeAsString(batch, mode: FileMode.append, flush: true); }
      catch (e) { storageError = e.toString(); }
    });
    return _writes;
  }
  Future<ShareResult?> shareLast() async {
    await flush();
    final content = _lastContent, name = _lastFileName;
    if (content == null || name == null) return null;
    final file = _file != null && storageError == null && await _file!.exists()
        ? XFile(_file!.path, mimeType: 'application/x-ndjson')
        : XFile.fromData(Uint8List.fromList(utf8.encode(content)), mimeType: 'application/x-ndjson');
    return SharePlus.instance.share(ShareParams(title: 'Log Convoy Mesh', files: [file], fileNameOverrides: [name]));
  }
  void _append(String category, String event, Map<String, Object?> data, {bool terminal = false}) {
    if (!terminal && _lines.length >= maxEvents - 1) { _droppedEvents++; return; }
    try {
      final now = DateTime.now().toUtc();
      final encoded = jsonEncode({
        'ts_utc': now.toIso8601String(), 'elapsed_ms': elapsed.inMilliseconds,
        'clock_delta_ms': now.difference(_startedAtUtc ?? now).inMilliseconds - elapsed.inMilliseconds,
        'session_id': _sessionId, 'device_id': _deviceId, 'device_name': _deviceName,
        'event_index': _lines.length, 'category': category, 'event': event, 'data': _safe(data),
      });
      _lines.add(encoded); _pending.add(encoded);
    } catch (_) { _droppedEvents++; }
  }
  static Object? _safe(Object? value, [int depth = 0]) {
    if (depth > 8) return '[depth_limit]';
    if (value is double && !value.isFinite) return null;
    if (value == null || value is num || value is bool) return value;
    if (value is String) return value.length > 4000 ? value.substring(0, 4000) : value;
    if (value is Map) return value.map((k, v) => MapEntry(k.toString(), _safe(v, depth + 1)));
    if (value is Iterable) return value.take(256).map((e) => _safe(e, depth + 1)).toList();
    return value.toString();
  }
  static String formatDuration(Duration value) =>
      '${value.inMinutes.remainder(60).toString().padLeft(2, '0')}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}
