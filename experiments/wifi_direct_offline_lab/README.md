# Wi-Fi Direct offline LAB — Convoy Mesh

**Stato aggiornato (2026-11-21):** primo gate implementato da Argon su ramo dedicato, commit eseguibile `37b348ef150315b4b955a5b7e8046aa1edc9cb2c`, HEAD documentale iniziale `fcbe98a99a5e32762973ef4e162e46da095f091b`. Report: 223 test Flutter superati e APK debug separato compilato; **nessuna prova Wi-Fi Direct fisica su due telefoni, nessuna integrazione con GPS/live position** (`BUILD_ONLY / PHONE_UNVERIFIED`). Ramo dedicato `experiment/wifi-direct-offline-lab-20261121`, derivato dalla beta Outdoor +20 (`fb77489a5fd58e9da56e7f763b1ea19eb8ec15e3`). Non modifica la beta firmata, non pubblica APK, non esegue upload cloud, non attiva PostHog o Rescue.

## Decisione successiva di Cama — una sola app sul telefono (2026-11-21)

Cama chiede di **mantenere un solo prodotto Convoy Mesh Outdoor installato** e aggiungere Wi-Fi Direct come opzione all'interno della stessa app, senza moltiplicare APK/lanciatori. **La sperimentazione resta interamente su questo ramo** fino a review e gate; nessun merge sulla beta Outdoor +20, nessuna pubblicazione o modifica al ramo `experiment/frontend-design-studio` (PR #9).

- **Passo intermedio:** riusare il laboratorio Wi-Fi Direct già implementato come pagina `Wi-Fi Direct LAB` accessibile da `Test log` (o area strumenti sperimentali) **nella stessa UI Outdoor**, senza presentarlo ancora come trasporto funzionante di posizioni GPS. Mantenere `BLE` come modalità corrente e predefinita; non introdurre ancora lo switch generale di trasporto.
- **Isolamento runtime obbligatorio:** l'attuale `AppShell._boot()` avvia `_ensureNearby()` e BLE e `didChangeAppLifecycleState(resumed)` può riavviarli. Prima di entrare in LAB bloccare ingresso se c'è un'uscita o registrazione diagnostica attiva (senza interromperle silenziosamente), sospendere/chiudere il BLE Nearby e la preview GPS di cui il LAB non è proprietario, e impedire il riavvio automatico di Nearby mentre il LAB è attivo. Preflight Bluetooth spento, Wi-Fi acceso, permessi e supporto hardware restano espliciti; nessun fallback BLE. Al ritorno dal LAB rilasciare socket, gruppo e receiver; riprendere Nearby **solo** quando la UI è in foreground e i prerequisiti sono soddisfatti, senza creare una traccia/FGS.
- **Isolamento dati:** non condividere ancora la pipeline di coordinate reali, storia/posizione live, identificativi persistenti né upload PostHog con il trasporto TCP non autenticato. Solo probe e ACK sintetici. Niente duplicazione della logica GPS/BLE.
- **Consegna a una sola app:** quando una variante integrata sarà ritenuta pronta per prova sul telefono, deve mantenere `applicationId=com.example.convoy_mesh.outdoor`, **la stessa firma permanente della beta Outdoor** (certificato SHA-256 `dd058e998369d9e3b46ae91e60177b95a31aa096a6ed04b9f7ba29142480f965`) e `versionCode > 20`. L'APK debug `.wifilab` esistente resta un artefatto di primo gate, non è l'aggiornamento installabile sopra Outdoor. Reutilizzare il workflow owner-protected e verificare installazione **senza disinstallazione e senza perdere dati**; non ri-firmare in chat e non attivare firma/release senza gate e approvazione previsti.
- **Prove prima della consegna:** review indipendente del codice e regressione navigazione/permessi/lifecycle/rientro BLE, build ed emulatore per la variante a una app; prova A/B Wi-Fi Direct reale su due telefoni con Bluetooth spento e Internet assente, perdita/ripresa e Stop. Restano separati gli esiti di unit test, build, emulatori, prove radio e aggiornamento firmato. Solo dopo un gate positivo e peer autenticati/canale cifrato si valuta una scelta BLE/Wi-Fi come veri trasporti GPS.

Questa **decisione aggiorna il packaging e l'esperienza d'uso del prossimo intervento**, non invalida l'isolamento della prima APK LAB già costruita. Le indicazioni sotto che richiedevano un `applicationId` distinto e vietavano un ingresso nella +20 erano **contratto del primo gate storico**, non obbligo di installare un'altra app per la fase seguente. **Secondo gate implementato nel ramo (commit codice `6915d4b5a43a47d624fc4ba764159ee47f197b39`):** ingresso nella stessa `AppShell` Outdoor dalla toolbar `Test log` dietro `CONVOY_WIFI_DIRECT_LAB_INTEGRATED=true`; blocco durante uscita/registrazione (con ricontrollo dopo cleanup), stop BLE Nearby e preview GPS, protezione del riavvio automatico nel lifecycle, route dedicata con `Stop` Wi-Fi prima del ritorno a Nearby. `pubspec.yaml` prenota +21, e la CI tenta un debug APK con il package `com.example.convoy_mesh.outdoor`, senza token PostHog. **Non ancora provato su radio fisica, né consegnato con firma beta permanente.** Prima del prossimo test sul telefono servono build/emulatore verdi, review indipendente e firma/upgrade +20→+21 con certificato invariato; il debug non è un aggiornamento installabile.

## Obiettivo e primo gate

Verificare se **due telefoni Android compatibili** possono:
1. tenere **Bluetooth spento** e **Internet non disponibile** (modalità aereo solo se Wi-Fi viene riabilitato manualmente e P2P supportato);
2. scoprire un peer Wi-Fi Direct e ottenere connessione reale senza router;
3. trasferire in entrambe le direzioni uno **stato sintetico non identificativo** con numero di sequenza, conferma applicativa e tempi locali;
4. riprendere dopo la perdita del collegamento senza duplicare consegne; smettere dopo Stop o uscita dalla pagina;
5. mostrare nel log il risultato reale e i fallimenti (non dedurre successo da discoverPeers/connect/associazione radio).

**Non inviare coordinate, nickname, ID persistenti, cronologie reali o dati diagnostici personali durante questo primo gate.** Gli strumenti BLE e PostHog della +20 restano fuori dal test. Un pacchetto riuscito non prova ancora accuratezza GPS né una rete multi-salto.

## Riuso / soluzione minima

Preflight Principle 11: (1) semplificato il requisito a connessione diretta e ping/ACK sintetici fra due dispositivi, senza coordinatore di mesh o Rescue; (2) riusare identità tecnica, contatori, separazione live/storico e pattern di test dell'app solo dopo il gate; (3–4) usare API Android di piattaforma `WifiP2pManager`, `WifiP2pConfig` e socket locali, **non aggiungere SDK terzi o server**; (5–6) un *lab Flutter isolato da compile-time flag* e un adapter nativo piccolo sono sufficienti al primo esperimento. Nessun nuovo motore GPS/BLE.

L'app lab deve usare **un applicationId distinto** (es. `com.example.convoy_mesh.wifilab`), icona/nome chiaramente LAB, build debug non distribuita come beta e un ingresso dedicato. Il flag di build non deve avviare `AppShell._boot`, `ConvoyMeshService.startNearby()` o `BackgroundRuntimeService`: altrimenti Bluetooth-off non è una prova pulita. Non aggiungere un selettore di trasporto alla +20 prima della prova. Nessun permesso di posizione concesso per dedurre una posizione dai peer Wi-Fi.

## Vincoli Android e sicurezza

- Verificare via `PackageManager` la disponibilità effettiva Wi-Fi Direct (non basta il Wi-Fi ordinario). Wi-Fi Direct richiede Wi-Fi attivo ma non Internet né router.
- `WifiP2pManager.discoverPeers()` e `connect()` con target Android 13+ richiedono `NEARBY_WIFI_DEVICES` (e richiesta a runtime); verificare anche `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`, `INTERNET` per i socket, l'eventuale stato Location e compatibilità Android precedenti. Non dichiarare `neverForLocation` se poi si ricava posizione fisica dalle informazioni dei peer.
- Consenso locale alla scelta del dispositivo e all'avvio del ping, nessuna connessione a sconosciuti in automatico.
- Soltanto stringhe/nonce sintetici nell'esperimento: **il traffico TCP del primo gate non è ancora autenticato per trasportare coordinate**. Prima dei dati reali serve pairing del gruppo, controllo dell'identità del peer, protezione crittografica dei messaggi, consenso dei partecipanti e regole di conservazione.
- Ogni evento di test locale distinguibile: `discover_requested`, `peer_seen`, `connect_requested`, `group_formed`, `socket_open`, `probe_sent`, `probe_received`, `ack_received`, `disconnect`, `error`. Eventi di sistema e messaggi applicativi sono prove diverse.
- Nessun identificativo Wi-Fi/MAC, nome dispositivo, SSID o coordinate in repository, artifact o log condivisi. Usare ID sintetici e conteggi; gli originali diagnostici restano privati. `Stop` e app in background devono chiudere risorse, ricevitore e socket, senza servizi in primo piano.
- Il Wi-Fi Direct **non garantisce** più metri del BLE in ogni scenario, né inoltro A→B→C. Queste restano prove future.

## Matrice di verifica (da eseguire, non già superata)

| Prova | Criterio |
| --- | --- |
| Static/test Flutter & Kotlin | Analisi, test controlli/permessi e build da commit esatto; nessun lavoro extra sulla +20 |
| Android A/B, BT spento | Entrambi mostrano assenza Bluetooth, Wi-Fi attivo; scoperta e connessione Wi-Fi Direct reali |
| Bidirezionale | Ogni telefono invia 20 probe sintetici, ACK con stesso nonce/seq, 0 false conferme; annotare perdite |
| Perdita/recupero | Allontanamento, riconnessione, deduplica e segnali temporali corretti |
| Campo, stessa configurazione | 10, 30, 50, 100, 150 m se fattibile; ambiente e ostacoli annotati, nessuna portata promessa |
| Schermo spento / OEM / batteria | Verificare separatamente; la simulazione non certifica radio reale o durata |
| Privacy e failure | Permesso negato, Wi-Fi disabilitato, nessun peer, Stop/uscita pagina, socket error: errori espliciti e nessun fallback BLE |

Solo dopo il gate positivo: aggiungere un `Transport` astratto riusando gli esistenti dati live/storici, identità/verifica, epoca e tempo della misura. Vietato mostrare come posizione corrente una storia vecchia; orologi non sincronizzati; niente segnali inventati, nessuna stima metri da RSSI.

## Prossima esecuzione

**Codex/ChatGPT Work** su questo ramo per implementare *solo* il primo gate (discovery/connessione P2P + ping/ACK sintetici, Kotlin/Flutter, test, CI isolata, APK di test senza firma beta). Richiede ambiente Android eseguibile. Nessun merge, release, configurazione segreti, nuovi costi, PostHog o modifica della beta +20. Revisionare indipendentemente implementazione e prove. Confermare sul campo con due telefoni; se non disponibili, stato `BUILD_ONLY / PHONE_UNVERIFIED`.

Fonti di piattaforma: https://developer.android.com/develop/connectivity/wifi/wifip2p e https://developer.android.com/develop/connectivity/wifi/nsd-wifi-direct
