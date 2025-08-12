# Convoy Mesh (MVP)

App Android per seguire un gruppo in auto/trekking. Online usa internet, offline usa (in futuro) Bluetooth per "rilanciare" la posizione tra i membri a catena.

## Cosa c'è già
- Flutter app con:
  - Creazione/ingresso stanza (codice a 6 cifre).
  - Mappa OpenStreetMap (no Google API Key).
  - Posizione tua in tempo reale.
  - Simulazione di 2 peer attorno (in attesa di BLE reale).
  - Pulsanti rapidi: Trekking (UI), Pausa condivisione.

## Cosa manca da implementare (prossime versioni)
- Advertising/Scanning BLE reale con `flutter_reactive_ble`.
- Cifratura end-to-end dei beacon.
- Relay multi-hop con TTL e de-duplica.
- Mappe offline (tile MBTiles) per zone senza rete.
- Canale online E2E (Firebase/Cloudflare).

## Build cloud (senza Android Studio)
1. Crea un repository su GitHub e carica questa cartella.
2. Apri https://codemagic.io e collega il repo.
3. Scegli "Flutter App" e attiva build Android **debug** (apk).
4. Avvia la build: al termine ottieni il file APK scaricabile.

> In alternativa, usa GitHub Actions con il seguente workflow minimale (salvalo in `.github/workflows/flutter.yml`):
```yaml
name: Flutter Android Debug APK
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.22.0'
      - run: flutter pub get
      - run: flutter build apk --debug
      - uses: actions/upload-artifact@v4
        with:
          name: app-debug
          path: build/app/outputs/flutter-apk/app-debug.apk
```

Dopo la build, scarica l'APK da "Artifacts".

## Permessi richiesti (Android)
- Posizione (necessaria per GPS).
- Bluetooth (scan/advertise/connect) per modalità offline (in arrivo).
- Servizio in foreground per tracking affidabile.

## Test rapido
- Installa l'APK su 2 telefoni Android.
- Apri l'app su entrambi.
- Sul primo: "Crea stanza" → vedi il codice in alto nella mappa.
- Sul secondo: "Entra nella stanza" con lo stesso codice.
- Con internet vedrai la mappa OSM; con poca rete vedrai comunque la tua posizione GPS. Nelle prossime versioni la posizione dei compagni arriverà via Bluetooth anche senza rete.

## Note
- Le coordinate dei peer ora sono simulate ogni 5s (placeholder).
- La zona iniziale è Mantova (~45.156, 10.792) se il GPS non è ancora disponibile.
