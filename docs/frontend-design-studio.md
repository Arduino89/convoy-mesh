# Convoy Mesh — Outdoor Premium Design & Customiser

Evoluzione grafica dell'interfaccia **Convoy Mesh** sul ramo sperimentale dedicato `experiment/frontend-design-studio` (PR #9 in bozza), basata sul checkpoint `c56b8c329f7d6880c54f4270b96fd3b7aa66096b` (`experiment/diagnostic-control-20261114`, PR #8, `0.7.7-diaglab+15`).

Su indicazione di progetto (**scelta esclusiva Outdoor Premium**):
- Le direzioni esplorative **Tactical Explorer** e **Minimal Adventure** restano archiviate e congelate nel checkpoint GitHub `5dbdedf0834a4581479d49e3817292d69bc1d665` e non vengono ulteriormente sviluppate.
- Tutta l'interfaccia dell'applicazione (**Radar BLE**, **Mappa**, **Test diagnostico**, **Bottom Dock**, schede cloud/ping, pannelli avanzati e finestre di dialogo) è ora coerente con l'identità **Outdoor Premium**.
- Resta sempre disponibile il ritorno immediato alla grafica **Originale (LAB +15)** (`DesignDirection.classic`).

Nessun file funzionale di rete BLE, filtraggio GPS, gestione tracce, foreground service runtime o upload/consenso diagnostico è stato modificato: il livello grafico consuma snapshot read-only.

## Modalità grafiche e 4 palette Outdoor curate

| Modalità / Palette | Identità visiva | Canvas / Accento / Evidenza | Contrasto verificato |
| :--- | :--- | :--- | :--- |
| **Originale (`LAB +15`)** | Seed Material 3 `blueGrey`, layout diagnostico originale | Sistema Material 3 | Baseline |
| **Outdoor · Pino & Carta** *(default Outdoor)* | Carta calda topografica, verde pino alpino e ocra ambrata | `#F2EEE4` / `#24503F` / `#B06C14` | Corpo **>= 7:1 (WCAG AAA)**, accento/stati **>= 4.5:1** |
| **Outdoor · Cresta Alba** | Pietra chiara ad altissimo contrasto sotto sole diretto | `#EFECE4` / `#1B4234` / `#A35D0A` | Corpo **>= 7:1 (WCAG AAA)**, accento/stati **>= 4.5:1** |
| **Outdoor · Terra & Rame** | Sentieri rocciosi, terracotta calda e muschio scuro | `#F3ECE3` / `#683722` / `#265743` | Corpo **>= 7:1 (WCAG AAA)**, accento/stati **>= 4.5:1** |
| **Outdoor · Abete Notturno** | Modalità crepuscolo/notte a basso abbagliamento nel bosco | `#0D1511` / `#76D1A1` / `#EAB056` | Corpo **>= 7:1 (WCAG AAA)**, accento/stati **>= 4.5:1** |

Tutti i contrasti e la leggibilità su display compatti (`360 dp` a scala testo `1.3x`) sono verificati automaticamente in `ConvoyMeshApp/test/design_studio_test.dart`.

## Estensione coerente a tutta l'app

- **Shell & Controllo uscita** (`ConvoyMeshApp/lib/design/shell/designed_app_shell.dart`): `DesignedBottomDock` con CTA uscita ad alto contrasto (`>= 52 dp`), superfici tattili pulite su `Material` dedicati e conservazione esatta delle etichette funzionali (`Radar BLE`, `Mappa`, `Test log`, `Avvia uscita`, `Uscita attiva • Termina uscita`).
- **Radar BLE** (`ConvoyMeshApp/lib/ble/ble_page.dart`, `lib/design/radar/designed_radar_view.dart`, `radar_scope.dart`, `radar_components.dart`): hero scuro con curve di livello topografiche configurabili, blip interattivi bidirezionali con lista partecipanti, badge stato Bluetooth toccabile, pannello **Modalità Vicini** espandibile e dialoghi Outdoor per nome dispositivo, diagnostica BLE e guida **?**.
- **Mappa** (`ConvoyMeshApp/lib/pages/map_page.dart`, `lib/design/map/designed_map_chrome.dart`): `DesignedMapScaffold` con griglia topografica offline coerente con la palette attiva, marker vettoriali utente/peer (`DesignedMapMarker`), pillola stato GPS in testa, controlli a portata di pollice (`Centra su di me`, toggle griglia offline), foglio legenda e conferma prima di cancellare la traccia locale.
- **Test diagnostico e schede PostHog** (`ConvoyMeshApp/lib/pages/diagnostic_page.dart`, `detailed_diagnostic_upload_card.dart`, `manual_ping_card.dart`, `lib/design/diagnostic/designed_diagnostic_header.dart`, `lib/design/outdoor_components.dart`): `DesignedDiagnosticStatusStrip` (badge `File locale` / `Solo memoria`, timer su 4 minuti, contatori), CTA `Avvia registrazione diagnostica • max 4 min` garantito **sopra la piega** su display `360x640`, schede `OutdoorCard` / `OutdoorSpecRow` / `OutdoorCallout` su `DetailedDiagnosticUploadCard` e `ManualPingCard`, con pieno rispetto dei blocchi di consenso e token esistenti.

## Studio di personalizzazione su 6 assi (`OutdoorCustomConfig`)

Il livello di personalizzazione (`ConvoyMeshApp/lib/design/outdoor_config.dart`, `outdoor_copy.dart`, `design_controller.dart`, `studio/frontend_design_studio_page.dart`) separa completamente i parametri visivi dai dati funzionali:

1. **Colori**: scelta tra le 4 palette curate e override individuali ARGB per *Sfondo canvas*, *Superficie card*, *Accento CTA*, *Evidenza*, *Hero radar*, *Stato positivo*, *Avviso* e *Critico*, con ricalcolo automatico del contrasto su testi e superifci.
2. **Caratteri**: scelta indipendente delle famiglie tipografiche bundled OFL (`Fraunces`, `Manrope`, `JetBrainsMono` o *Sistema*) per display, corpo e valori numerici, fattore di scala testo (`0.88x..1.24x`), peso titoli (*bold*) ed etichette maiuscole.
3. **Dimensioni**: raggio angoli piccolo/medio/grande, spessore bordi, target touch minimo per guanti (`48..64 dp`), diametro avatar peer, scala icone, proporzione scope Radar e ombreggiatura schede (`elevated`).
4. **Spaziature**: unità base griglia (`3.0..5.5 dp`), scala margini schermata, padding interno schede e distanza tra sezioni.
5. **Animazioni**: switch globale e rispetto automatico di `MediaQuery.disableAnimations`, rotazione fascio Radar, pulsazione live GPS/BLE, curve di livello topografiche, periodo rotazione (`2400..9500 ms`) e durate transizioni (`fast`/`medium`).
6. **Testi**: 17 token di copy visivo (`OutdoorCopyTokens`) personalizzabili (kicker, titoli schermata, sottotitoli, didascalia radar, intestazioni sezioni e CTA non critiche), mantenendo bloccati tutti gli ID di protocollo, gli schemi JSON diagnostici e le etichette di smoke test.

Tutte le impostazioni restano esclusivamente in locale tramite `SharedPreferences` (`design_studio.direction`, `design_studio.outdoor_config`), con esportazione/importazione JSON integrata nello Studio e ripristino immediato dei valori predefiniti.

## Come provare e tornare alla grafica originale

1. L'APK sperimentale privato **Convoy Outdoor LAB** (`com.example.convoy_mesh.outdoor`, `0.7.7-outdoor+16`, compilato con `--dart-define=CONVOY_DEFAULT_OUTDOOR=true`) si avvia direttamente in **Outdoor Premium** ed è installabile **fianco a fianco** rispetto a `Convoy Mesh` e `Convoy Diagnostics LAB`.
2. Tocca l'icona tavolozza (`palette_outlined`) nell'angolo in alto a destra di **Radar BLE**, **Mappa** o **Test diagnostico**.
3. Puoi:
   - selezionare istantaneamente **Originale (LAB +15)** per ripristinare in un tap la grafica originale Material 3;
   - scegliere una delle 4 palette Outdoor (*Pino & Carta*, *Cresta Alba*, *Terra & Rame*, *Abete Notturno*);
   - aprire **Personalizza in Outdoor Studio** per modificare tutti i 6 assi dal vivo, confrontare **Originale vs Outdoor** nello stesso scenario sintetico e importare/esportare il JSON di stile.

## Semantica onesta e dati sintetici

- Gli anelli del `RadarScope` rappresentano **solo le 4 fasce qualità RSSI BLE** (`Ottimo`, `Buono`, `Medio`, `Scarso`) e un angolo deterministico dell'ID utente, **mai distanza reale né orientamento bussola**; la didascalia resta visibile sotto lo scope.
- Tutte le anteprime dello Studio e i file PNG in `docs/design-previews/` usano esclusivamente le fixture sintetiche in `ConvoyMeshApp/lib/design/studio/synthetic_radar_fixtures.dart`.

## Anteprime renderizzate in Flutter (`docs/design-previews/`)

Renderizzate su frame `390x844` (`dpr 2.0`) con font OFL reali (`Fraunces`, `Manrope`, `JetBrainsMono`) via `ConvoyMeshApp/test/render_design_previews_test.dart`:

- `01_original_radar.png` — Originale `LAB +15` (scenario sintetico Gruppo in cammino)
- `02_outdoor_radar.png` — Outdoor Premium *Pino & Carta* (Radar BLE top + scope topografico)
- `03_outdoor_peers.png` — Outdoor Premium *Pino & Carta* (lista partecipanti e pannello *Modalità Vicini*)
- `04_outdoor_map_cresta.png` — Mappa Outdoor *Cresta Alba* (uscita attiva, incertezza e traccia peer `HISTORY` tratteggiata)
- `05_outdoor_map_abete_notturno.png` — Mappa Outdoor *Abete Notturno* (modalità bosco/crepuscolo)
- `06_outdoor_diagnostic_top.png` — Test diagnostico (acquisizione attiva, controlli primari sopra la piega e barra stato)
- `07_outdoor_diagnostic_summary_cloud.png` — Test diagnostico (riepilogo tecnico locale e scheda opt-in PostHog EU)
- `08_outdoor_studio_customizer.png` — Outdoor Studio (pannello personalizzazione su 6 assi e selettore palette)

## Dipendenze, asset e packaging privato

- **Zero nuove dipendenze**: `ConvoyMeshApp/pubspec.lock` è identico alla baseline (`flutter pub get --enforce-lockfile` verificato).
- Rimossi i font delle direzioni archiviate (`SpaceGrotesk`, `PlusJakartaSans`); restano solo i `.ttf` statici e licenze OFL di `Fraunces`, `Manrope` e `JetBrainsMono`.
- `ConvoyMeshApp/android/app/build.gradle.kts`, `tools/android_smoke.sh` e `.github/workflows/android-debug.yml` configurati per generare e validare l'APK privato affiancabile **`Convoy Outdoor LAB`** (`com.example.convoy_mesh.outdoor`, `versionCode 16`, `0.7.7-outdoor+16`, nessuna Release pubblica o merge).

## Verifiche eseguite e limiti aperti

- `flutter pub get --enforce-lockfile`: esito positivo, zero modifiche a `ConvoyMeshApp/pubspec.lock`.
- `flutter test --no-pub --reporter expanded`: **183/183 test superati** (168 test baseline invariati + 14 test su Outdoor Premium, WCAG AAA/AA, config su 6 assi, adapter read-only, `360x640` CTA sopra la piega e schede cloud in `ConvoyMeshApp/test/design_studio_test.dart` + 1 skip protetto per `render_design_previews_test.dart`).
- `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`: **26 segnalazioni preesistenti** nel codice baseline, **0 errori e 0 nuovi warning/info** sui file del design system o test introdotti.
- `dart run tool/pedestrian_candidate_probe.dart candidate`: esito positivo invariato.
- Build APK + smoke test Android API 35 su GitHub Actions (`.github/workflows/android-debug.yml`): in verifica sul commit eseguibile corrente.
- **Limiti noti**: l'emulatore CI non sostituisce prove sul campo con due smartphone fisici all'aperto (visibilità alla luce diretta, notch reali, uso con guanti, BLE reale e GNSS reale).
