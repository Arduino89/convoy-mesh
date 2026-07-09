import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class MyLocationMapPage extends StatefulWidget {
  const MyLocationMapPage({super.key});

  @override
  State<MyLocationMapPage> createState() => _MyLocationMapPageState();
}

class _MyLocationMapPageState extends State<MyLocationMapPage>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();

  StreamSubscription<ServiceStatus>? _serviceSub;
  StreamSubscription<Position>? _posSub;

  LatLng? _myLatLng;
  double? _accuracyMeters;
  DateTime? _lastFixAt;

  bool _serviceEnabled = false;
  bool _permissionOk = false;

  String _status = "In attesa…";

  late final AnimationController _blinkCtrl;
  late final Animation<double> _blinkAnim;

  @override
  void initState() {
    super.initState();

    _blinkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _blinkAnim = Tween<double>(begin: 0.25, end: 1.0).animate(
      CurvedAnimation(parent: _blinkCtrl, curve: Curves.easeInOut),
    );

    _initAndListen();
  }

  Future<void> _initAndListen() async {
    await _refreshPrereqsAndStreams();

    // 🔥 Questa è la parte che evita “esci/rientra”
    _serviceSub?.cancel();
    _serviceSub = Geolocator.getServiceStatusStream().listen((status) async {
      await _refreshPrereqsAndStreams();
    });
  }

  Future<void> _refreshPrereqsAndStreams() async {
    final enabledNow = await Geolocator.isLocationServiceEnabled();

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    final permOk = permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;

    _serviceEnabled = enabledNow;
    _permissionOk = permOk;

    if (!enabledNow) {
      await _stopPositionStream();
      _setStatus("Location disattivata (accendila nelle impostazioni).");
      _setBlinking(false);
      setState(() {});
      return;
    }

    if (!permOk) {
      await _stopPositionStream();
      _setStatus(permission == LocationPermission.deniedForever
          ? "Permesso posizione negato per sempre (vai in impostazioni)."
          : "Permesso posizione negato.");
      _setBlinking(false);
      setState(() {});
      return;
    }

    // Se arrivo qui: servizio ON e permessi OK.
    _setStatus(_myLatLng == null ? "GPS attivo: aggancio in corso…" : _status);
    _setBlinking(_myLatLng == null); // lampeggia finché non abbiamo fix

    await _startPositionStream();
    setState(() {});
  }

  Future<void> _startPositionStream() async {
    if (_posSub != null) return;

    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 2,
      ),
    ).listen((pos) {
      final ll = LatLng(pos.latitude, pos.longitude);
      _myLatLng = ll;
      _accuracyMeters = pos.accuracy;
      _lastFixAt = DateTime.now();

      _setBlinking(false); // fix ottenuto -> verde fisso
      _setStatus(
        "GPS OK: ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)} "
            "(±${pos.accuracy.toStringAsFixed(0)}m)",
      );

      if (mounted) setState(() {});
    }, onError: (e) {
      _setStatus("Errore GPS: $e");
      _setBlinking(true);
      if (mounted) setState(() {});
    });
  }

  Future<void> _stopPositionStream() async {
    await _posSub?.cancel();
    _posSub = null;
  }

  void _setStatus(String s) {
    _status = s;
  }

  void _setBlinking(bool blinking) {
    if (blinking) {
      if (!_blinkCtrl.isAnimating) {
        _blinkCtrl.repeat(reverse: true);
      }
    } else {
      if (_blinkCtrl.isAnimating) {
        _blinkCtrl.stop();
        _blinkCtrl.value = 1.0;
      }
    }
  }

  int _gpsBarsFromAccuracy(double? acc) {
    if (acc == null) return 0;
    if (acc <= 5) return 4;
    if (acc <= 10) return 3;
    if (acc <= 25) return 2;
    if (acc <= 50) return 1;
    return 0;
  }

  Color _gpsColor() {
    if (!_serviceEnabled || !_permissionOk) return Colors.red;
    // servizio ON + permessi OK
    return Colors.green;
  }

  bool _isAcquiring() {
    // “aggancio in corso” = servizio ON + permessi OK ma senza fix recente
    if (!_serviceEnabled || !_permissionOk) return false;
    if (_myLatLng == null) return true;

    // se il fix è vecchio, consideriamolo di nuovo in acquiring
    final last = _lastFixAt;
    if (last == null) return true;
    final age = DateTime.now().difference(last);
    return age > const Duration(seconds: 6);
  }

  Widget _gpsIndicator() {
    final bars = _gpsBarsFromAccuracy(_accuracyMeters);
    final acquiring = _isAcquiring();
    final color = _gpsColor();

    final icon = Icon(Icons.gps_fixed, color: color, size: 24);

    final iconWidget = acquiring
        ? FadeTransition(opacity: _blinkAnim, child: icon)
        : icon;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        iconWidget,
        const SizedBox(width: 6),
        _GpsBars(bars: bars, color: color),
        const SizedBox(width: 8),
      ],
    );
  }

  @override
  void dispose() {
    _serviceSub?.cancel();
    _posSub?.cancel();
    _blinkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final center = _myLatLng ?? const LatLng(45.0, 10.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Mappa - La mia posizione"),
        actions: [
          Tooltip(
            message: _status,
            child: Center(child: _gpsIndicator()),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_status),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 16,
              ),
              children: [
                TileLayer(
                  urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                  userAgentPackageName: "com.example.convoy_mesh",
                ),
                if (_myLatLng != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _myLatLng!,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.my_location, size: 36),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _myLatLng == null
                        ? null
                        : () => _mapController.move(_myLatLng!, 17),
                    child: const Text("Centra su di me"),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GpsBars extends StatelessWidget {
  final int bars; // 0..4
  final Color color;

  const _GpsBars({required this.bars, required this.color});

  @override
  Widget build(BuildContext context) {
    // 4 barrette stile “segnale”
    const heights = [6.0, 10.0, 14.0, 18.0];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (i) {
        final active = i < bars;
        return Container(
          width: 4,
          height: heights[i],
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: active ? color : Colors.grey.withOpacity(0.35),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}
