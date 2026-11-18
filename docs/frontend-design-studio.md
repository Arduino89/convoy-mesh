# Convoy Mesh — Frontend Design Studio

Studio esplorativo dell'interfaccia utente per **Convoy Mesh** su ramo indipendente `experiment/frontend-design-studio`, basato sul checkpoint `c56b8c329f7d6880c54f4270b96fd3b7aa66096b` (`experiment/diagnostic-control-20261114`, PR #8, `0.7.7-diaglab+15`).

Nessun file funzionale di rete BLE, filtraggio GPS, gestione tracce, foreground service runtime o upload/consenso diagnostico è stato modificato: il livello grafico consuma snapshot read-only e può tornare istantaneamente all'interfaccia **Originale (LAB +15)**, che resta il default attivo.

## Le quattro direzioni disponibili in app

| Direzione | Identità visiva | Tipografia bundled (OFL) | Scope Radar | Target touch minimo |
| :--- | :--- | :--- | :--- | :--- |
| **Originale** *(default)* | Seed Material 3 `blueGrey`, layout LAB +15 invariato | Sistema | Anelli diagnostici originali | `48 dp` |
| **Outdoor Premium** | Carta calda (`#F2EEE4`), pino scuro (`#24503F`), ocra (`#C8862A`) | `Fraunces` (display) + `Manrope` | Hero scura con curve di livello topografiche (`contour`) | `52 dp` |
| **Tactical Explorer** | HUD OLED notturno (`#090D0C`), verde segnale (`#8CF5B4`), ambra (`#FFB648`) | `SpaceGrotesk` + `JetBrainsMono` (dati tabulari) | Scansione a fascio rotante con tacche radiali (`sweep`) | `52 dp` |
| **Minimal Adventure** | Bianco sporco (`#F5F5F2`), nero (`#0F1113`), arancio sicurezza (`#FF5A1F`) | `PlusJakartaSans` (monofamiglia geometrica) | Onde concentriche pulsanti (`pulse`) | `56 dp` |

Tutte e tre le nuove palette rispettano contrasto **WCAG AAA (>= 7:1)** tra testo e sfondo principale e **>= 4.5:1** per testo secondario e pulsanti primari (verificato in test automatico `ConvoyMeshApp/test/design_studio_test.dart`).

## Architettura separata e personalizzabile

- **Token centralizzati** (`ConvoyMeshApp/lib/design/design_tokens.dart`, `design_presets.dart`, `design_theme.dart`): `ConvoyDesignTokens` è una `ThemeExtension<ConvoyDesignTokens>` unica per palette, font, pesi, raggi, bordi, spaziature e durate. I tre preset vivono esclusivamente in `DesignPresets`.
- **Preferenza locale reversibile** (`ConvoyMeshApp/lib/design/design_controller.dart`): `DesignDirectionController` salva solo in locale la chiave `design_studio.direction` tramite `SharedPreferences` (già presente nelle dipendenze), senza mai scrivere nei log diagnostici né inviare eventi cloud.
- **Bridge read-only dal vivo** (`ConvoyMeshApp/lib/design/radar/radar_live_adapter.dart`, `radar_view_data.dart`, `radar_actions.dart`): mappa gli stati reali di `ConvoyMeshService`, `LocationFusionService` e `BackgroundRuntimeService` in uno snapshot immutabile senza alterare sequenze, contatori o permessi.
- **Componenti tematici condizionali**:
  - Radar BLE: `DesignedRadarView` + `RadarScope` (3 composizioni distinte: `heroCard`, `hud`, `editorial`; selezione peer bidirezionale su blip/scheda; rispetto di `MediaQuery.disableAnimations`).
  - Shell & Controllo uscita: `DesignedBottomDock` (pulsante uscita ad alto contrasto per uso con guanti + tab bar preservando esattamente `Radar BLE`, `Mappa`, `Test log` ed etichette `Avvia uscita` / `Uscita attiva • Termina uscita`).
  - Mappa: `DesignedMapScaffold` + `DesignedMapMarker` con griglia cartografica offline integrata sotto `FlutterMap`, pillola stato GPS in testa, legenda spiegata (incertezza vs percorso HISTORY) e conferma prima di cancellare la propria traccia.
  - Diagnostica: `DesignedDiagnosticStatusStrip` con indicatore live, badge `File locale` / `Solo memoria`, barra di avanzamento sul limite di 4 minuti e contatori tabulari, mantenendo invariati controlli, enum tester e consensi di `DiagnosticPage`.

## Semantica onesta (nessuna distorsione dei dati)

- Gli anelli del `RadarScope` codificano esclusivamente le **4 fasce di qualità segnale BLE RSSI** di `ConvoyMeshService.rssiQuality` (`Ottimo`, `Buono`, `Medio`, `Scarso`) e un angolo deterministico dall'ID utente (`angleFor`), **mai distanza metrica né direzione geografica**. La didascalia esplicita resta sempre visibile sotto lo scope.
- Tutti gli screenshot e il Design Studio usano esclusivamente gli scenari sintetici definiti in `ConvoyMeshApp/lib/design/studio/synthetic_radar_fixtures.dart`.

## Come provare le varianti nell'app

1. Dalla schermata attiva (**Radar BLE**, **Mappa** o **Test diagnostico**), tocca l'icona tavolozza (`palette_outlined`) nella barra superiore.
2. Nel foglio inferiore scegli direttamente uno stile (`Originale`, `Outdoor Premium`, `Tactical Explorer`, `Minimal Adventure`) per applicarlo dal vivo all'intera app, oppure tocca **"Confronta varianti nel Design Studio"**.
3. Dentro **Design Studio** (`FrontendDesignStudioPage`) puoi:
   - commutare le 4 direzioni estetiche e gli scenari sintetici (`Gruppo in cammino (3)`, `Uscita GPS attiva`, `Solo ricerca (0 peer)`, `Bluetooth spento`);
   - navigare tra le anteprime **Radar BLE**, **Mappa** e **Test log**;
   - ispezionare palette esadecimale, contrasti e parametri tipografici tramite il pulsante impostazioni (`tune`), e applicare lo stile scelto con **Applica**.

## Anteprime renderizzate in Flutter (`docs/design-previews/`)

Renderizzate su frame telefono logico `390x844` (dpr `2.0`) con i font OFL effettivamente inclusi in `ConvoyMeshApp/assets/fonts/` tramite `ConvoyMeshApp/test/render_design_previews_test.dart`:

- `01_original_radar.png` — Originale LAB +15 (scenario sintetico Gruppo in cammino)
- `02_outdoor_premium_radar.png` — Outdoor Premium (Radar BLE top + scope topografico)
- `03_outdoor_premium_peers.png` — Outdoor Premium (lista partecipanti scrollata)
- `04_tactical_explorer_radar.png` — Tactical Explorer (HUD notturno + uscita GPS attiva + scope `sweep`)
- `05_minimal_adventure_radar.png` — Minimal Adventure (contatore editoriale + scope `pulse`)
- `06_map_outdoor_premium.png` — Mappa Outdoor Premium (reticolo offline + marker peer/self + dock a una mano)
- `07_map_tactical_explorer.png` — Mappa Tactical Explorer (ricerca GPS su sfondo scuro)
- `08_diagnostic_outdoor_premium.png` — Schermata Test diagnostico con `DesignedDiagnosticStatusStrip` attivo
- `09_design_studio.png` — Pagina interattiva Design Studio con selettore direzione/scenario

## Dipendenze e asset

- Nessun nuovo pacchetto in `pubspec.yaml`; `ConvoyMeshApp/pubspec.lock` invariato (`flutter pub get --enforce-lockfile` verificato).
- Aggiunti esclusivamente i file statici `.ttf` e le relative licenze `OFL-*.txt` in `ConvoyMeshApp/assets/fonts/`.

## Verifiche eseguite e limiti aperti su questo ramo

- `flutter pub get --enforce-lockfile`: esito positivo, zero modifiche a `pubspec.lock`.
- `flutter test --no-pub --reporter expanded`: **179/179 test superati** (168 preesistenti + 10 nuovi in `test/design_studio_test.dart` + 1 skip sicuro per `render_design_previews_test.dart` in modalità standard).
- `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`: **28 segnalazioni preesistenti** nel codice baseline, **0 errori e 0 nuovi warning/info** sui file introdotti o modificati.
- `dart run tool/pedestrian_candidate_probe.dart candidate`: esito positivo invariato.
- **Limiti aperti**: in questo container non è disponibile l'Android SDK/emulatore né un dispositivo fisico, quindi non sono ancora stati eseguiti build APK locale, smoke test Android (`tools/android_smoke.sh`) e verifica visiva/permessi dal vivo su smartphone reale (luce solare esterna, Android 10–15, tall screen/notch). Inoltre `.github/workflows/android-debug.yml` non ha trigger automatico `push` per il nome ramo `experiment/frontend-design-studio` (eseguibile via `workflow_dispatch` manuale o su PR verso `main`).
