# Wi-Fi Direct offline LAB — Convoy Mesh

**Stato:** mandato di esperimento approvato da Cama il 2026-11-21; *progettazione, non implementazione o prova su telefoni*. Ramo dedicato `experiment/wifi-direct-offline-lab-20261121`, derivato dalla beta Outdoor +20 (`fb77489a5fd58e9da56e7f763b1ea19eb8ec15e3`). Non modifica la beta firmata, non pubblica APK, non esegue upload cloud, non attiva PostHog o Rescue.

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
