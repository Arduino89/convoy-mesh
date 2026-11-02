// Synthetic-only, independent Android package. Execution evidence is in the report.
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

const token = String.fromEnvironment('POSTHOG_PROJECT_TOKEN');
const ingestionHost = String.fromEnvironment('POSTHOG_HOST');
const localReceiver = bool.fromEnvironment('LAB_LOCAL_RECEIVER');
const runId = String.fromEnvironment('LAB_RUN_ID');
const queueSize = int.fromEnvironment('LAB_QUEUE_SIZE', defaultValue: 1000);
const buildSource = String.fromEnvironment('BUILD_COMMIT', defaultValue: 'unbuilt');
const nativeFilter = bool.fromEnvironment('LAB_NATIVE_FILTER');
const revokeMode = String.fromEnvironment('LAB_REVOKE_MODE', defaultValue: 'optOut');
const nativeLab = MethodChannel('convoy.telemetry.lab/native');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Trial()));
}

class Trial extends StatefulWidget {
  const Trial({super.key});
  @override
  State<Trial> createState() => _TrialState();
}

class _TrialState extends State<Trial> {
  SharedPreferences? _prefs;
  bool _consent = false, _ready = false, _busy = false, _sdk = false;
  int _sequence = 0, _refused = 0;
  bool _actionOk = true;
  Map<String, dynamic> _sentinels = {};
  String _status = 'Caricamento';

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      // Authenticated local Dart VM service only; same methods as LAB buttons.
      // No production instrumentation and no reflection into SDK internals.
      developer.registerExtension('ext.convoyTelemetryLab.control', (_, args) async {
        if (args['run_id'] != runId || !_ready || _busy) {
          return developer.ServiceExtensionResponse.error(-32000, 'Wrong run or lab not ready');
        }
        final action = args['action'];
        switch (action) {
          case 'grant': await _action(_grant);
          case 'revoke': await _action(_revoke);
          case 'generate10': await _action(() => _generate(10));
          case 'generate45': await _action(() => _generate(45));
          case 'generate100': await _action(() => _generate(100));
          case 'flush': await _action(_flush);
          case 'status': break;
          default:
            return developer.ServiceExtensionResponse.error(-32000, 'Unknown lab command');
        }
        return developer.ServiceExtensionResponse.result(jsonEncode({
          'run_id': runId, 'consent': _consent, 'requested': _sequence,
          'refused': _refused, 'sdk': _sdk, 'status': _status,
          'scope': 'INTENT_NOT_DELIVERY',
          'action_ok': _actionOk, 'revoke_mode': revokeMode,
          'native_filter': nativeFilter, 'sentinels': _sentinels,
        }));
      });
    }
    _action(_load);
  }

  Future<void> _action(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    _actionOk = true;
    try {
      await task();
    } catch (e) {
      _actionOk = false;
      _consent = false;
      await _prefs?.setBool('consent', false);
      if (nativeFilter) { await nativeLab.invokeMethod('revoke'); }
      else if (_sdk) { await Posthog().optOut(); }
      // No diagnostic text or exception is uploaded.
      _status = 'Errore locale: ${e.runtimeType}. Prova non valida; controllare il debugger privato.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    if (!RegExp(r'^synthetic-[a-z0-9-]{1,48}$').hasMatch(runId) ||
        ![32, 1000].contains(queueSize)) {
      throw StateError('Supply a unique synthetic LAB_RUN_ID and queue 32 or 1000');
    }
    _prefs = await SharedPreferences.getInstance();
    if (nativeFilter) {
      if (!localReceiver || !['optOut', 'resetClose'].contains(revokeMode)) {
        throw StateError('Native correction probe is local fake-token only');
      }
      _sentinels = Map<String, dynamic>.from(
          (await nativeLab.invokeMapMethod<String, dynamic>(
              _prefs!.getString('run_id') == null ? 'seedSentinels' : 'sentinels'))!);
    }
    final previousRun = _prefs!.getString('run_id');
    if (previousRun != null && previousRun != runId) {
      throw StateError('New run requires a separate clean lab installation');
    }
    if (!await _prefs!.setString('run_id', runId)) throw StateError('Storage');
    _consent = _prefs!.getBool('consent') ?? false;
    _sequence = _prefs!.getInt('sequence') ?? 0;
    _refused = _prefs!.getInt('refused') ?? 0;
    if (_consent) {
      await _setup();
      if (nativeFilter) await nativeLab.invokeMethod('grant');
    }
    _ready = true;
    _status = 'Pronto; invio effettivo e cancellazione remota non attestati.';
  }

  Future<void> _setup() async {
    if (_sdk) return;
    if (localReceiver && token.isNotEmpty) {
      throw StateError('Local receiver accepts only the built-in fake token');
    }
    if (!localReceiver && (token.isEmpty || ingestionHost != 'https://eu.i.posthog.com')) {
      throw StateError('Project token and verified EU ingestion host are required');
    }
    if (nativeFilter) {
      await nativeLab.invokeMethod('setup', {'run_id': runId, 'queue_size': queueSize});
      _sdk = true;
      return;
    }
    final config = PostHogConfig(localReceiver ? 'phc_synthetic_local_only' : token)
      ..host = localReceiver ? 'http://10.0.2.2:8765' : ingestionHost
      ..optOut = !_consent
      ..personProfiles = PostHogPersonProfiles.never
      ..captureApplicationLifecycleEvents = false
      ..sessionReplay = false
      ..surveys = false
      ..preloadFeatureFlags = false
      ..sendFeatureFlagEvent = false
      ..capturePushNotificationSubscriptions = false
      ..capturePushNotificationOpened = false
      ..debug = false
      ..maxQueueSize = queueSize
      ..flushAt = 20
      ..maxBatchSize = 20
      ..flushInterval = const Duration(seconds: 60);
    config.rageClickConfig.enabled = false;
    // Error autocapture defaults to false in the inspected version; do not install it.
    config.beforeSend = [(e) {
      const allowed = {'schema_version', 'run_id', 'event_id', 'sequence',
                       'event_name', 'synthetic'};
      final p = e.properties;
      if (!_consent || e.event != 'cm_lab_probe' || p == null ||
          p.keys.toSet().difference(allowed).isNotEmpty ||
          p.length != allowed.length || p['synthetic'] != true ||
          p['run_id'] != runId) {
        return null;
      }
      // Verified against this project's live GeoIP template before any cloud send.
      // This is a transport privacy control, not an additional business field.
      p[r'$geoip_disable'] = true;
      return e;
    }];
    await Posthog().setup(config);
    _sdk = true;
  }

  Future<void> _grant() async {
    if (!await _prefs!.setBool('consent', true)) throw StateError('Storage');
    _consent = true;
    await _setup();
    if (nativeFilter) { await nativeLab.invokeMethod('grant'); }
    else { await Posthog().optIn(); }
    if (nativeFilter) {
      _sentinels = Map<String, dynamic>.from(
          (await nativeLab.invokeMapMethod<String, dynamic>('sentinels'))!);
    }
    _status = 'Consenso TEST attivo. Controllare anche la riapparizione di vecchi eventi.';
  }

  Future<void> _revoke() async {
    _consent = false; // Block capture immediately, including on persistence failure.
    final persisted = await _prefs!.setBool('consent', false);
    if (_sdk) {
      if (nativeFilter) { await nativeLab.invokeMethod('revoke'); }
      else { await Posthog().optOut(); }
    }
    if (!persisted) throw StateError('Consent persistence failed');
    if (_sdk && nativeFilter && revokeMode == 'resetClose') {
      // Experimental public-API combination: NOT claimed to purge the queue.
      await nativeLab.invokeMethod('resetClose');
      _sdk = false;
    }
    if (nativeFilter) {
      _sentinels = Map<String, dynamic>.from(
          (await nativeLab.invokeMapMethod<String, dynamic>('sentinels'))!);
    }
    // Intentionally exercise native optOut. reset()/close() are not assumed to purge.
    _status = 'Revocato. Svuotamento coda NON dimostrato: verificare dopo riavvio e nuovo consenso.';
  }

  Future<void> _generate(int count) async {
    if (!_consent) {
      _refused += count;
      if (!await _prefs!.setInt('refused', _refused)) throw StateError('Storage');
      _status = 'Tentativi rifiutati; SDK non invocato.';
      return;
    }
    await _setup();
    if (_sequence + count > 5000) throw StateError('Lab run capped at 5000 requests');
    for (var i = 0; i < count; i++) {
      // The oracle records intent BEFORE the SDK call; it is not an SDK delivery ACK.
      final seq = _sequence + 1;
      if (!await _prefs!.setInt('sequence', seq)) throw StateError('Storage');
      _sequence = seq;
      final properties = <String, Object>{
        'schema_version': 1, 'run_id': runId,
        'event_id': '$runId-${seq.toString().padLeft(6, '0')}',
        'sequence': seq, 'event_name': 'cm_lab_probe', 'synthetic': true,
      };
      if (nativeFilter) {
        await nativeLab.invokeMethod('capture', {'properties': properties});
      } else {
        await Posthog().capture(eventName: 'cm_lab_probe', properties: properties);
      }
    }
    _status = 'Richiesti $_sequence eventi. Ricezione da verificare sul backend.';
  }

  Future<void> _flush() async {
    if (!_consent || !_sdk) {
      _status = 'Invio bloccato dal consenso.';
      return;
    }
    if (nativeFilter) { await nativeLab.invokeMethod('flush'); }
    else { await Posthog().flush(); }
    _status = 'Invio richiesto: il completamento non dimostra ricezione.';
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _ready && !_busy;
    Widget button(String label, Future<void> Function() action) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: ElevatedButton(onPressed: enabled ? () => _action(action) : null,
                            child: Text(label)),
    );
    return Scaffold(appBar: AppBar(title: const Text('Convoy • Telemetry LAB')),
      body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('SOLO DATI SINTETICI — prova non integrata in Convoy Mesh.'),
          const Text(localReceiver ? 'Destinazione: ricevitore locale, NON PostHog Cloud.'
                                   : 'Destinazione: PostHog EU.'),
          Text('Run: $runId\nCoda: $queueSize\nBuild: $buildSource'),
          Text('Consenso: $_consent • richiesti: $_sequence • rifiutati: $_refused'),
          button('Consenti raccolta di prova / riattiva', _grant),
          button('Genera 10 eventi', () => _generate(10)),
          button('Genera 100 eventi', () => _generate(100)),
          button('Genera 45 eventi (coda 32)', () => _generate(45)),
          button('Richiedi invio', _flush),
          button('Rifiuta / revoca raccolta', _revoke),
          Text(_status),
          const SizedBox(height: 16),
          SelectableText(jsonEncode({'run_id': runId, 'requested_count': _sequence,
            'refused_attempts': _refused, 'consent': _consent, 'queue_size': queueSize,
            'build_source': buildSource, 'scope': 'INTENT_NOT_DELIVERY'})),
        ])));
  }
}
