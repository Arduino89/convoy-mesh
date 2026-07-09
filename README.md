# Convoy Mesh

App Flutter Android per condividere posizione tra telefoni vicini usando BLE advertising/scanning e GPS.

## Stato

Snapshot sorgente sincronizzato da sviluppo locale. Versione di lavoro: **v0.3**.

## Cosa fa ora

- Radar BLE con peer rilevati.
- Mappa con posizione propria e peer.
- Protocollo BLE con pacchetti POS e NAME separati.
- Parsing manufacturer data con magic `CM` anche a offset 2.
- Debug BLE/peer per test su due telefoni.
- Cambio ID protetto da pressione lunga.

## Struttura

```text
ConvoyMeshApp/
  lib/
  android/
  pubspec.yaml
  pubspec.lock
```

## Build locale

```bash
cd ConvoyMeshApp
flutter pub get
flutter run
```

Per generare un APK debug:

```bash
flutter build apk --debug
```

L'APK sarà in:

```text
ConvoyMeshApp/build/app/outputs/flutter-apk/app-debug.apk
```

## Note

Non sono tracciati file generati come `build/`, `.dart_tool/`, `.idea/`, `.gradle/` e APK.
