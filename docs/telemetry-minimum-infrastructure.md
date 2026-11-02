# Convoy Mesh — valutazione telemetria minima

Data aggiornamento: 2 novembre 2026. Corretto il verificatore di identità; nuove prove Android ancora non eseguite.

## Esecuzione GitHub autorizzata il 2 novembre

Autorizzati pubblicazione del solo laboratorio, workflow dedicato e PR in bozza sul ramo `experiment/telemetry-runtime-lab`, base operativa `2d8a50a`. Il nuovo workflow prova prima Android con la piccola app indipendente. I risultati SDK saranno eseguiti soltanto dopo quel gate; al caricamento iniziale restano non verificati. Convoy, workflow precedenti, merge e release rimangono fuori dalle modifiche. Solo runner standard pubblico `ubuntu-24.04`, dati sintetici, nessun segreto o APK negli artifact.

## Revisione del 2 novembre: identità e ambiente

Il controesempio allegato alla review è confermato: il contratto permetteva soltanto `distinct_id == run_id`, mentre il verificatore accettava anche UUID estranei. Due regressioni nuove sono fallite sul codice precedente e passate dopo la correzione. Ora il confronto è esatto e un valore estraneo produce `invalid_distinct_id`, viene oscurato nella ricevuta e fa fallire l’audit anche se HTTP risponde 200. Il campo `uuid` dell’evento rimane distinto ed è preservato; le righe ricevute restano visibili per riconciliare consegna e privacy separatamente. Questo corregge il controllo, non dimostra il comportamento del SDK. La suite finale passa **56/56**: 42 controlli del kit dopo il fix più 14 controlli delle guardie del nuovo protocollo Android. La revisione indipendente è statica; il codice nativo della piccola app non è stato compilato in questa sessione.

Il pacchetto v2 è stato recuperato e verificato tramite SHA-256 `a19e33ec5f8cd843166a2bd118c70fbc807427b79701bb7fedde4d2277cdc689`. Il workspace ripartiva da un checkpoint precedente: sorgenti ed evidenze sono ripristinati senza sostituire gli esiti storici. Le due APK precedenti e la toolchain non sono presenti nell’ambiente attuale: non vengono dichiarate riutilizzate o ricompilate.

Il controllo dell’ambiente trova assenti ADB, emulatore, Flutter, compilatore Java e `/dev/kvm`; nessun dispositivo Android collegato o altro esecutore Android è esposto. Non è stato riavviato l’emulatore software guasto. Il controllo nativo indipendente è predisposto in `tools/telemetry_spike/runtime_control/`: deve dimostrare boot completo, installazione, apertura, arresto e riapertura con PID nuovo e stato conservato, prima di qualsiasi fase di telemetria. Il runner ora richiede una ricevuta completa del controllo: stesso seriale e avvio Android, otto fasi riuscite, identità/hash APK e osservazioni di entrambi gli avvii; le etichette PASS da sole non bastano. La sua build e la sua esecuzione sono **NOT_RUN**, non successi ricavati dai test Python.

Esiste un’alternativa storicamente collaudata: il runner standard `ubuntu-24.04` del [run Convoy 37198612027](https://github.com/Arduino89/convoy-mesh/actions/runs/37198612027). Il flusso attuale esegue Convoy e non accetta la nuova app di controllo o il laboratorio: un semplice rerun non soddisfa il mandato. Per usarlo occorre un job dedicato su ramo isolato. La bozza locale non modifica `.github/workflows` e non è attiva; nessun push o job remoto è stato avviato. Il repository è stato riconfermato pubblico e GitHub documenta gratuità dei runner standard pubblici e accelerazione Android; questo non attesta un nuovo run riuscito né autorizza runner a pagamento. [Fonte GitHub](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

**Stato del mandato:** difetto del verificatore corretto; ambiente Android non ancora disponibile; revoca, nuovi eventi, sentinelle e payload finale del SDK ancora da eseguire. Nessuna nuova ingestione PostHog, nessuna spesa, pubblicazione o raccolta reale. PR #4 riconfermata aperta/draft, HEAD `2d8a50af9c151d29f7b1ed13e02b1643d404aa09`; Convoy e workflow invariati.

## Stato storico del 1 novembre

Data: 1 novembre 2026. Follow-up: **correttivo candidato preparato; nuove prove Android bloccate dall’ambiente, non superate**. Esito precedente: **PostHog Cloud EU + Data candidato preferito; percorso sintetico verificato, integrazione nell’app Convoy NON eseguita e adozione NON approvata.**

Nel ciclo precedente, la prova Python e il controllo di ingestione/lettura **PostHog Cloud EU** sono conclusi. La build Android del laboratorio con il vero SDK è riuscita. Il percorso **SDK Android offline → riavvio del processo → PostHog → analisi Data è riuscito: 100/100 ID, zero mancanti/duplicati**. La revoca ha invece fallito il requisito di eliminazione: **20/20 eventi revocati sono ricomparsi dopo nuovo consenso**. Minimizzazione dei metadati, saturazione e risorse fisiche sono indicati separatamente. La saturazione nativa conferma la consegna dei soli ultimi 32 eventi su 45 richiesti. Nessuna spesa, pubblicazione o raccolta da utenti reali.

## Follow-up: revoca mirata e verifica prima di PostHog

Il seguito del 1 novembre resta nel package LAB: nessun codice, dipendenza, workflow o APK Convoy è modificato. Le nuove richieste hanno come unica destinazione configurata un ricevitore locale con token fittizio; nessun inoltro al cloud. I risultati storici PostHog 100/100, revoca 20/20 e overflow 32/45 restano separati.

**Modifica predisposta:** un piccolo binding Android usa il SDK ufficiale 3.75.0/core6.48.0 e installa `addBeforeSend` sulla configurazione prima di `PostHogAndroid.setup`. La coda, il batching e il trasporto restano quelli del vendor. Il filtro mantiene i sei campi sintetici dell’oracolo e i due controlli `$geoip_disable=true`/`$process_person_profile=false`; sostituisce l’identità dell’evento con il solo run sintetico. Le informazioni di protocollo (UUID, timestamp, batch, routing e codifica) hanno una lista separata motivata. Qualsiasi arricchimento successivo non ammesso deve far fallire il controllo della richiesta finale. Un filtro sul server non viene usato come correttivo.

**Revoca da mettere alla prova:** ricerca documentale tramite il collegamento PostHog e inventario pubblico del binario effettivamente compilato non hanno trovato una API pubblica di purga della coda. `reset` è documentato per logout/identità; `flush` è asincrono e non garantisce ricezione. Il nuovo caso prova `optOut → reset → optOut → close` senza cancellare file del SDK o dell’app. Le sole chiamate ritornate non attestano eliminazione. I20 vecchi ID devono restare assenti dopo riavvio e nuovo consenso offline; i 10 nuovi devono arrivare. Una preferenza separata e un file sintetico devono mantenere valore/hash. Non viene proposto `pm clear` come revoca.

L’oracolo registra gli ID prima delle catture; gli errori del laboratorio hanno `action_ok=false` e disattivano la raccolta. Il ricevitore ispeziona anche eventi automatici, percorsi, header e contenuto del batch, conservando chiavi/violazioni e oscurando valori sconosciuti. La controprova ACK perso salva il batch, sincronizza il file e chiude la connessione senza risposta: gli UUID permettono di riconoscere un ritentativo reale. I45 ID della saturazione restano tutti nell’oracolo; nessun denominatore ridotto ai 32 sopravvissuti.


### Esiti effettivi del follow-up

| Controllo nuovo | Esito |
|---|---|
| Compilazione SDK/binding e APK x86_64 | PASS, sorgente `90b9e0d519249f196b2ebd52e22aae23d52be82e` |
| Analizzatore Flutter | PASS, nessun problema rilevato |
| Controlli Python | 40/40 PASS: 25 precedenti + 15 del ricevitore finale |
| Revoca offline → riavvio → consenso offline → rete, vecchi0/nuovi 10 | **NOT_RUN**, nessuna nuova evidenza del SDK |
| Whitelist finale, consegna normale, rifiuto, ACK perso, saturazione della nuova configurazione | **NOT_RUN**, nessun risultato dedotto dalla compilazione |
| Nuove richieste al ricevitore locale |0; non è un PASS del rifiuto, perché il LAB non è partito |

APK di prova verificata: `telemetry-native-review-x86-001.apk`, 76.992.737 byte, SHA-256 `fed32365a4df7553bf1c0315406062a8102dd7a65f5b3eec7bde8c0f645b27e8`, package LAB, versione 0.0.1/versionCode 4001, minSDK 24/target 36, solo x86_64. Identità/firma/permessi nella ricevuta. Variante cap32 predisposta: run `synthetic-native-overflow-002`, 117.081.743 byte, SHA-256 `88e96fc73b6cabc84c759dc6f97545259b38123ba5153af3c4443bd35b6fa2c1`. Le dimensioni di build debug incrementali non sono confronti di peso release. APK non pubblicate o consegnate come candidate Convoy.

Il primo avvio ha raggiunto il boot ma l’installazione non si è conclusa nella finestra osservata. Al successivo tentativo l’installatore restituisce `Broken pipe (32)`; il PID del servizio di sistema cambia e compaiono `DeadSystemException`, prima di eseguire il laboratorio. Un’immagine pulita dello stesso emulatore riproduce boot incompleto e servizio input interrotto/assente. Questo reset riguarda soltanto l’ambiente sintetico, **prima dei test**: non è una prova di revoca. La causa di fondo non è stabilita. Non è un fallimento attribuito al SDK e non modifica gli esiti storici della vecchia build.

Chiusura: arrestato l’emulatore di prova e il ricevitore, server ADB terminato. Il processo dell’ultimo emulatore termina con SIGSEGV dopo la richiesta di chiusura; difetto registrato, non nascosto come uscita regolare. Nessuna raccolta rimasta attiva. Il pacchetto esclude APK, credenziali, connessioni debugger, schermate e log diagnostici completi.

**Decisione:** non dichiarare risolta né la purga né la minimizzazione finale. Il filtro nativo è un correttivo candidato compilato e revisionato, non ancora verificato sul filo. `resetClose` è una controprova preparata, non una purga supportata attestata. Per completare il mandato serve un runtime Android stabile; non occorre un nuovo accesso PostHog. Eventuale confronto eseguito Firebase richiede progetto/app Spark e lettura dell’export autorizzata, tuttora non disponibile qui. Nessuna spesa, pubblicazione, push o attivazione reale autorizzata/eseguita.

Le prove storiche che seguono restano valide per le rispettive build: **100 corretti, 20 revocati riapparsi, 13 mancanti a saturazione**. Non vengono riciclate come test del nuovo binding. Batteria/GPS/Bluetooth fisici conservano i gate già previsti.

### Confronto Firebase sugli stessi requisiti

| Requisito | PostHog nel laboratorio | Firebase documentato, non eseguito |
|---|---|---|
| Purga della sola Analytics locale | Nessuna API dedicata trovata nella superficie pubblica consultata; reset/close da misurare, senza assumere purga. | `resetAnalyticsData()` elimina Analytics locale e rinnova app-instance ID; non cancella lo storage generale dell’app. Contratto senza ACK di purga durabile: stesso test riavvio/sentinelle necessario. |
| Rifiuto e revoca | Gate applicativo persistente + optOut; non equivale a eliminazione. | `setAnalyticsCollectionEnabled(false)` persistente e `setConsent`; combinare con reset, senza inferire zero traffico dal solo consenso negato. |
| Payload finale minimo | Hook nativo pubblico predisposto; prova finale predisposta sul ricevitore locale, **NOT_RUN**. | API Android/Flutter consultate senza filtro pubblico del payload serializzato finale. Disabilitare pubblicità/screen tracking non dimostra assenza degli altri dati automatici. |
| Saturazione e duplicati | Cap32 verificato storicamente; nuovi controlli con oracolo e UUID. Nessun contatore produttivo di scarto dimostrato. | Nessun cap/callback di scarto o ACK per evento trovato nelle API consultate. Stesso oracolo e finestra adeguata, senza trasferire risultati PostHog. |
| Fonte per Data e costi | Collegamento PostHog già disponibile; nuove prove locali senza spesa. | Spark+BigQuery Sandbox possibile; niente intraday, export e consolidamento differiti. Accesso BigQuery qui non disponibile; nessun progetto/piano attivato. |

Firebase è un candidato più esplicito sul reset locale, **non un’alternativa già conforme alla minimizzazione o migliore nei test**. Nessun fork del SDK o uploader produttivo è stato costruito. Se la purga richiede accesso ai file interni, mantenere un fork o sostituire il trasporto, la scelta deve tornare a questo confronto e a una prova Firebase con gli stessi ID/sentinelle, senza adottare un hack.

Fonti PostHog consultate tramite docs-search: [Android/configurazione](https://posthog.com/docs/libraries/android#all-configuration-options), [reset/logout](https://posthog.com/docs/libraries/android#reset-after-logout), [Flutter/beforeSend](https://posthog.com/docs/libraries/flutter#amending-or-dropping-events), [offline](https://posthog.com/docs/libraries/android#offline-behavior). Fonti Firebase: [API Android](https://firebase.google.com/docs/reference/android/com/google/firebase/analytics/FirebaseAnalytics), [API FlutterFire](https://pub.dev/documentation/firebase_analytics/latest/firebase_analytics/FirebaseAnalytics-class.html), [raccolta](https://firebase.google.com/docs/analytics/android/configure-data-collection), [dati automatici](https://support.google.com/analytics/answer/11582702?hl=en), [export](https://firebase.google.com/docs/projects/bigquery-export). I controlli granulari GA non attestano da soli il punto di filtraggio sul telefono; DebugView/BigQuery sono osservazioni dopo ricezione.

Limiti invariati: nessun telefono fisico, consumo/OEM non misurato, nessuna prova GPS/Bluetooth nuova; arresto ordinato dopo persistenza, non interruzione durante scrittura/revoca o richiesta in volo. La mancata osservazione in una finestra breve non prova una cancellazione permanente. La revisione statica indipendente del nuovo harness ha fatto correggere ordine di inizializzazione, fallimento esplicito, sentinelle e controlli di rete; non è approvazione d’adozione.


## Decisione e perimetro del ciclo precedente

Mantenere **PostHog EU + Data come candidato per il laboratorio**, con **adozione bloccata** nella configurazione provata. Il percorso di consegna funziona, ma la revoca non elimina la coda e la whitelist Dart non limita i metadati nativi. Firebase Analytics + BigQuery resta alternativa documentale, non soluzione già validata per questi difetti. La preferenza deriva dalla coda esplicita, dalla possibilità di interrogare gli eventi e dalla disponibilità del collegamento PostHog in questo account. Non è una prova che PostHog perda meno eventi, consumi meno batteria o sia già conforme alla configurazione privacy desiderata.

Nell'immediato, i log diagnostici già presenti in Convoy restano locali. Non vanno inoltrati: il recorder contiene nome, ID del telefono, coordinate ed eventuali note libere. Telemetria tecnica aggregata e diagnostica dettagliata rispondono a esigenze diverse.

Base verificata: [PR #4](https://github.com/Arduino89/convoy-mesh/pull/4), ramo `experiment/pedestrian-acquisition-v1`, HEAD `2d8a50af9c151d29f7b1ed13e02b1643d404aa09`, usato come base del checkout isolato. README e CONTINUITY letti a questo SHA. `main` è precedente e non è stato usato come base. La prova fisica di 0.7.7-exp1+9 resta aperta; lo studio non la sostituisce.

## Confronto

| Aspetto | PostHog + Data | Firebase Analytics + BigQuery + Data |
|---|---|---|
| Flutter/Android | Flutter 3.47.4 e pacchetto PostHog Flutter 5.58.3 compilati e provati nel percorso offline/riavvio/cloud. Dipendenze native: `posthog-android` 3.75.0 e core 6.48.0 bloccati nei lock. | Supporto Flutter ufficiale; richiede progetto Firebase, configurazione Android e librerie FlutterFire. Risoluzione dipendenze e build non eseguite. |
| Offline | Coda su disco, limite configurabile, scarto dei più vecchi a saturazione. `capture`/`flush` non sono ricevute del server. | Raccolta gestita dal SDK; nessun contratto di coda configurabile equivalente dimostrato nelle API consultate. Durabilità, saturazione e ripartenza da misurare. Non assumere assenza di perdite. |
| Analisi | Collegamento PostHog **installato e verificato**: query reali nel progetto EU 330212. Data applicato agli ID completi: controllo API 10/10 e SDK Android 100/100, più controprova della revoca. | Il plugin Firebase è disponibile ma non installato. BigQuery risulta **DISABLED_BY_ADMIN / NOT_AVAILABLE** qui: nessuna lettura diretta eseguita. Un export privato può alimentare Data, ma non dimostra collegamento automatico. |
| Costo iniziale | Piano gratuito documentato: 1 milione di eventi/mese, senza carta; oltre la quota il piano a consumo parte da $0,00005/evento. Account osservato su piano free, senza abbonamento attivo o customer di fatturazione; quota 1.000.000, un solo progetto. Nessun piano a pagamento attivato. | Analytics gratuito. Spark consente BigQuery Sandbox senza passare automaticamente a Blaze; non è obbligatorio pagare per una piccola prova. |
| Limiti analitici | Le query sono adatte a questa piccola prova; evitare un nuovo processo ETL o esportazioni massive ricorrenti via `/query`. | Export giornaliero e latenza da considerare. Sandbox: 10 GiB di storage lifetime, 1 TiB di query/mese, scadenza automatica dopo 60 giorni, niente streaming. |
| Privacy | EU, profili disattivati e GeoIP escluso verificati. Revoca: 20/20 eventi della coda ricompaiono alla riadesione. 38 proprietà native: filtro Dart insufficiente per la minimizzazione. Opt-out uso per modelli non verificato. | Configurazione proposta, non eseguita: disabilitare raccolta iniziale, Advertising ID e personalizzazione; richiedere consenso esplicito. Verificare eventi automatici, metadati e cancellazione. |
| Manutenzione | Bloccare sia pacchetto Dart sia dipendenze native Gradle: il lock Dart da solo non congela Android. Un provider e una connessione già verificata; correttivi per revoca e filtri nativi ancora da dimostrare. | FlutterFire + Firebase/GA + export BigQuery + autorizzazioni dataset/query; più passaggi per lo specifico obiettivo di analisi esterna. Può convenire se si adotta già l'ecosistema Firebase. |

Fonti primarie: [PostHog Flutter](https://posthog.com/docs/libraries/flutter), [pacchetto 5.58.3](https://pub.dev/packages/posthog_flutter/versions/5.58.3), [sorgente ispezionato](https://github.com/PostHog/posthog-flutter/tree/5d8eaaa8c68612f345f945d44a9c88c8315286aa), [Firebase Flutter](https://firebase.google.com/docs/analytics/flutter/get-started), [prezzi PostHog](https://posthog.com/product-analytics/pricing), [prezzi Firebase](https://firebase.google.com/pricing), [export Firebase](https://firebase.google.com/docs/projects/bigquery-export), [limiti Sandbox](https://docs.cloud.google.com/bigquery/docs/sandbox), [query PostHog](https://posthog.com/docs/api/queries). Costi e capacità sono quelli documentati alla consultazione, non un preventivo contrattuale.

## Risultati in sintesi del ciclo precedente

| Prova | Risultato osservato | Decisione |
|---|---|---|
| SDK offline → processo riavviato → PostHog → Data | 100/100 ID, zero mancanti o duplicati; invariato dopo due flush aggiuntivi | PASS nel perimetro emulatore debug |
| Rifiuto | 10 tentativi iniziali e 10 dopo revoca bloccati | PASS nei casi provati |
| Revoca di 20 accodati, riavvio e riadesione | Tutti i 20 riappaiono senza nuove catture | FAIL: adozione bloccata |
| Saturazione, coda 32 e 45 richieste | Ricevuti solo 14..45, mancanti 1..13 | Scarto previsto osservato; nessuna garanzia senza perdite |
| Minimizzazione nativa | 38 chiavi nelle proprietà; nome emulatore `emu64x` | Lista ammessa Dart insufficiente prima di usare dati reali |
| IP/GeoIP/profili sui 100 eventi normali | Flag corretti, zero IP/città/coordinate memorizzati; conferma finale su tutti i 162 eventi sintetici | Verificato nei tre run |
| Batteria, traffico radio e limiti OEM | Solo campione cumulativo UID emulatore; nessun telefono disponibile | Budget traffico e batteria NOT_MEASURED, protocollo preparato |

## Riferimento Python, distinto dal SDK

Il workflow Data di qualità dei dati è stato applicato ai risultati del laboratorio Python: unità di analisi = un evento sintetico identificato da `run_id + sequence`. Confronto fra insieme atteso e righe ricevute; duplicati conservati e misurati, eventi rifiutati/revocati separati dalle perdite. Script, input e risultati sono riproducibili nel [kit](../tools/telemetry_spike/README.md).

Il laboratorio usa SQLite e un ricevitore HTTP sulla stessa macchina. Esegue veri processi distinti, un'interruzione dopo scritture confermate, connessioni rifiutate e successivi invii su loopback. **Non usa il SDK PostHog/Firebase e non è un'implementazione destinata all'app.**

| Scenario locale | Tentati | Attesi dopo consenso | Righe ricevute | Unici ricevuti | Mancanti | Duplicati |
|---|---:|---:|---:|---:|---:|---:|
| Offline, processo terminato, riavvio, ricevitore raggiungibile | 100 | 100 | 100 | 100 | 0 | 0 |
| Coda limitata a 32, prodotti 45 | 45 | 45 | 32 | 32 | 13 | 0 |
| Ricezione avvenuta, prima conferma fallita, ritentativo | 10 | 10 | 20 | 10 | 0 | 10 |
| Revoca di 20 accodati, riavvio e nuovo consenso | 20 | 0 | 0 | 0 | 0 | 0 |
| Rifiuto iniziale | 20 | 0 | 0 | 0 | 0 | 0 |

Controlli automatici: **25/25 passati** (10 riferimento, 4 ricevitore SDK, 6 payload cloud, 5 normalizzazione query). Comprendono il controesempio in cui conteggio atteso e ricevuto coincidono ma nascondono una perdita e un duplicato, ID di un'altra prova, oracolo duplicato, dati vietati e limiti in byte. La saturazione e la conferma fallita sono guasti introdotti intenzionalmente: il risultato utile è che l'analisi li rileva.

Nel caso da 100 eventi: 5 richieste al ricevitore, 14.697 byte di corpi JSON e database SQLite da 32.768 byte. Sono misure del laboratorio, **non** traffico TLS, memoria RAM, storage SDK o consumi Android. Nella prova con limite payload 400 byte, 300 inserimenti restano nel limite e gli scarti vengono contati. La dimensione su disco non coincide con il limite del contenuto: SQLite mantiene pagine e journal.

Nessun dato proveniente dai telefoni degli utenti è stato analizzato. Nessun test su GPS, BLE, schermo spento, OEM o batteria è deducibile da questi risultati.

## Controllo cloud realmente eseguito

Progetto [PostHog EU 330212](https://eu.posthog.com/project/330212/pipeline), nuovo e inizialmente vuoto, piano gratuito. Run `synthetic-cloud-control-001`: 10 eventi inviati via API Python il 1 novembre alle 19:46:59–19:47:04 UTC. HTTP 200, corpo richiesta 4.023 byte, nessun ritentativo automatico. La successiva query tramite il connettore restituisce **10 righe, 10 ID unici, 0 mancanti, 0 duplicati, 0 inattesi e 0 conflitti**. Risposta completa sotto il limite di 500 righe, finestra esplicita e oracolo separato.

Data è qui il workflow di analisi: lettura della fonte PostHog, normalizzazione rigorosa, riconciliazione Python e ricevuta. Non è un secondo sistema di raccolta e non è stato pubblicato un dashboard. Il kit include la risposta effettiva della query e il normalizzatore eseguibile `query_receipt.py`; un risultato al limite, incompleto o con tipi inattesi non viene classificato come completo.

`anonymize_ips=true` e replay disattivato erano già impostati nel progetto. La trasformazione GeoIP era invece attiva: il template live conferma che `$geoip_disable=true` evita l'arricchimento. Tutti i 10 eventi hanno questo flag e `$process_person_profile=false`. La query mirata trova 0 IP e 0 città/latitudine/longitudine memorizzati. Gli avvisi sulle proprietà assenti sono conservati nella ricevuta; i nomi controllati vengono dal template reale, non da una supposizione di tassonomia. Nessuna impostazione globale di PostHog è stata cambiata. L'opt-out di utilizzo per modelli non è attestato: tutti i dati inviati sono sintetici.

**Questo è un controllo API → PostHog → analisi, non prova del SDK mobile offline.** UUID generati dal client Python; i risultati non dimostrano la deduplicazione del SDK nativo. Il token di sola ingestione resta in un file privato, escluso dal repository e dal pacchetto.

## Build Android verificata

Laboratorio distinto: `com.cama.telemetry.convoy_telemetry_lab`, versione 0.0.1+1, minSDK 24, target 36. Flutter 3.47.4, PostHog Flutter 5.58.3, Android 3.75.0 e core 6.48.0. Gradle 8.14, AGP 8.11.1, Kotlin 2.2.20, coerenti con la base Convoy; il tooling segnala supporto in prossima dismissione, da pianificare separatamente. Nessuna modifica di dipendenze dell'app Convoy.

La prima APK eseguita è **solo ricevitore locale** (`LAB_LOCAL_RECEIVER=true`), sorgente `e395a4b930139cca683e533b3967f9713c706867`, SHA-256 `09881f5cc352e75f0dbc83aaafb78af7c40c9d7165fc30a8381034eaa3186bf4`, 155.895.180 byte. Certificato debug SHA-256 `d0cafb94c0a582df917617a30c23818508d0ff53afad95bd301b57c2c28c0bb8`. Ricevuta di package/firma nel pacchetto; nessun permesso GPS, BLE, camera o microfono. Il campione aggiornato aggiunge host EU verificato e flag GeoIP: questi cambiamenti successivi non sono attribuiti retroattivamente alla prima APK.

L'ambiente è stato preparato qui: emulatore Android 35 x86_64 senza KVM, avvio e installazione riusciti, rallentamenti/System UI ANR osservati. RAM, tempi e batteria di questo ambiente non rappresentano un telefono. Dopo tutte le query e lo stop del LAB, lo spegnimento richiesto dell’emulatore termina con SIGSEGV; il difetto di chiusura è registrato e non viene nascosto come uscita regolare. Nessuna APK Convoy ricompilata o sostituita.

La variante successiva per PostHog EU è stata compilata dal commit `02034a0222c464ae28a7d0d9e5f6d64cd18c0139`: SHA-256 `1a40224f35610eabe654f57e2631d85e147bc25e580c67f9454688edf91fd73e`, 155.896.762 byte, build 60,9 s. Include i controlli GeoIP, push automatici disabilitati e un'estensione di test soltanto debug. Il test chiama gli stessi comandi dei pulsanti, senza intervenire sulla coda interna. Le due APK e i loro risultati non sono intercambiabili.

Il proxy gestito è usato anche dall'emulatore; il certificato pubblico è un'ancora di fiducia limitata al debug, senza disattivare TLS. Non è una configurazione proposta per l'app Convoy. Il progetto Firebase non è stato attivato o compilato: il suo confronto resta documentale.

## Risultati del runtime Android

Il controllo iniziale del laboratorio rifiuta 10 richieste prima del consenso (`sdk=false`, sequenza 0), con query cloud a zero. In modalità aereo verificata (`wifi_on=0`, `mobile_data=0`, rete predefinita assente) il vero SDK accetta la richiesta di 100 eventi; prima della riconnessione il backend ne vede zero. Dopo force-stop e apertura esplicita, PID cambiato da 4865 a 5115, contatore 100 ripristinato ancora offline. Dopo riconnessione osservata e richiesta di invio, query completa: **100 righe, 100 ID unici, zero mancanti/inattesi/duplicati/conflitti**. Due flush aggiuntivi mantengono 100 righe e 100 unici. Non è un kill durante scrittura, un riavvio del sistema operativo o un invio mentre l'app rimane force-stopped. Il caso di conferma HTTP persa dopo accettazione è stato forzato solo nel riferimento Python: i due flush nativi senza duplicati non lo sostituiscono.

Un campione prima del consenso misura 190.461 KiB PSS e 60.368 KiB di dati del package; dopo inizializzazione e 100 richieste offline: 236.115 KiB PSS e 61.120 KiB. Differenze di 45.654 KiB PSS e 752 KiB su disco **includono riscaldamento della build debug e non isolano il costo del SDK**. Nessuna stima produttiva di RAM/traffico/batteria deriva da questi due campioni. Un successivo campione NetworkStats del solo UID LAB riporta 15.210 byte TX e 10.685 RX nella cronologia disponibile: valori cumulativi fra le varianti e limitati all’ultimo poll, senza baseline OFF/ON. Non sono un totale completo del test, byte dei corpi TLS o un budget radio certificato; il dump completo non è salvato. La dimensione dei dati esclude l'APK ma include cache dell'app.

## Saturazione nativa: perdita misurata

Run distinto `synthetic-android-overflow-001`, stesso sorgente `02034a0` e dipendenze, limite coda **32**. APK SHA-256 `6890e1d3ba2ddfb7d922a3d740061500a5d473c5d5a15cf77f016f253b593a30`, 195.987.727 byte, build 36,3 s; nessuna stima di dimensione release ricavata da queste APK debug. Richiesti 45 eventi in modalità aereo, force-stop e riapertura ancora offline, PID 6218 → 6433 e intenzione 45 ripristinata. Dopo riconnessione e flush: **32 righe, 32 unici, ID 14..45**, zero duplicati/inattesi/conflitti. Gli ID 1..13 non sono ricevuti, coerentemente con lo scarto dei più vecchi documentato. Quota dell'oracolo ricevuta 32/45 = 71,11%; questo è un test di saturazione riuscito, non una consegna senza perdite.

Campioni di dati del solo package: 60.392 KiB prima del consenso, 60.664 KiB dopo 45 richieste offline, 60.440 KiB dopo riconnessione; PSS 236.530 → 235.558 → 233.555 KiB. Sono campioni di un emulatore debug, con cache e inizializzazione incluse: non dimostrano plateau prolungato, limite in byte a coda 1000, incremento RAM del solo SDK o risparmio di batteria. Non è stato aggiunto un contatore di scarti nel prodotto: la perdita è rilevata dall'oracolo esterno della prova.

## Revoca: requisito di eliminazione non superato

Nel run Android principale, dopo aver ricevuto 1..100, sono stati richiesti offline altri 20 eventi (101..120). `optOut()` è stato eseguito prima di riattivare la rete; ulteriori 10 tentativi sono stati rifiutati. Dopo force-stop e apertura, PID 5115 → 5730, il consenso resta falso e il SDK non viene inizializzato. Ripristinata la rete, il comando flush è bloccato e la query degli ID 101..120 restituisce zero.

Al successivo consenso esplicito e flush, **senza generare nuovi ID**, ricompaiono tutti i 20 eventi revocati. La prima osservazione ne vede 18; la successiva query di conferma e il dettaglio completo ne vedono 20 unici, senza duplicati. I due inizialmente non osservati non vengono classificati come perduti. L'oracolo ammissibile dopo revoca è vuoto: questi 20 sono inattesi, non una percentuale di consegna riuscita.

La prova distingue quindi due requisiti: blocco immediato/persistenza del rifiuto superati nel caso provato; **eliminazione della coda e non riapparizione dopo riadesione fallite**. Non riguarda l'eliminazione dei 100 già ricevuti prima della revoca, né la revoca durante una richiesta in volo. Ricevute, ID e query sono nel pacchetto.

Prima di adottare il SDK va dimostrata una cancellazione locale della sola telemetria e una minimizzazione del payload dopo l'arricchimento nativo. Il campione conserva il controesempio e non inserisce una cancellazione non verificata. `pm clear` è stato usato soltanto sul package LAB per isolare prove successive: non è una strategia di revoca accettabile per Convoy, perché cancellerebbe anche altri dati dell’app. Se servisse un uploader personalizzato o modifiche sostanziali al plugin, rivalutare il costo di manutenzione rispetto a Firebase prima di sceglierlo. Anche Firebase deve superare lo stesso test; non è promosso per assenza di prove negative.

## Configurazione minima proposta

Raccogliere solo pochi eventi espliciti e contatori aggregati, ad esempio avvio/fine uscita e un riepilogo tecnico al minuto. Niente evento per ogni posizione o pacchetto radio. Presenza BLE, età del fix e storia del percorso devono restare metriche separate; non stimare precisione reale dal valore di accuratezza del GPS.

Per la prova, l'evento `cm_lab_probe` ammette solo sei campi sintetici. Il campione Flutter ha package separato `com.cama.telemetry.convoy_telemetry_lab`, non richiede GPS/BLE e non legge il recorder Convoy. Non integra nuove dipendenze in `ConvoyMeshApp`.

PostHog parte solo dopo consenso, con lifecycle automatico, replay, survey, flag e log applicativi non utilizzati. Il controllo reale ha trovato **38 chiavi** nelle proprietà degli eventi nativi, di cui i sei campi applicativi. Fra le aggiunte: `$device_name`, modello/manufacturer, locale/timezone, sessione, user agent, dimensioni schermo e stati interni del SDK. Il nome del solo emulatore è `emu64x`, verificato su tutti i 100 eventi. Nessun nome umano è stato inviato, ma il filtro Dart **non limita il payload nativo alla whitelist**. Minimizzazione prima dell'invio ancora da risolvere e riprovare: un filtro server successivo non equivale a evitare che il dato arrivi al servizio. Impostare EU, scarto IP e disattivazione GeoIP prima del primo invio. Scartare l'IP memorizzato non impedisce al servizio di ricevere l'IP di rete. Identificativi casuali sono pseudonimi, non prova di anonimato.

La policy PostHog corrente prevede uso dei contenuti per sviluppo/propri modelli salvo accordo o opt-out. Verificare e disabilitare tale uso per il progetto di prova; non promettere che la regione EU lo escluda automaticamente. [Privacy e controlli storage](https://posthog.com/docs/privacy/data-storage), [policy corrente](https://posthog.com/privacy).

La revoca deve bloccare nuove acquisizioni e invii, sopravvivere al riavvio e impedire che una nuova adesione riattivi gli eventi revocati. **Il campione misura `optOut()`; non afferma che cancelli la coda.** `reset()` cambia identità/proprietà e non è assunto equivalente a una cancellazione. Se manca un meccanismo affidabile per eliminare solo dati di telemetria, fermare l'adozione. La cancellazione di dati già sul server è un'operazione distinta. Per Firebase verificare `setAnalyticsCollectionEnabled`, `setConsent` e `resetAnalyticsData`, senza confondere reset locale e cancellazione server. [API Android Firebase](https://firebase.google.com/docs/reference/android/com/google/firebase/analytics/FirebaseAnalytics), [configurazione raccolta](https://firebase.google.com/docs/analytics/android/configure-data-collection).

## Risorse e soglie da misurare

Proposte iniziali, non risultati né promesse: coda 1.000 eventi, invii in gruppi da 20 con intervallo 60 s; nessun invio senza consenso. A 60 eventi/ora la sola coda da 1.000 copre al massimo 16 h 40 min, meno con eventi aggiuntivi. Eventi persi per saturazione devono restare visibili nella riconciliazione; non esiste ancora un contatore di scarti SDK verificato.

Scenario di costo, non previsione utenti: 100 tester × 8 uscite/mese × 4 ore × 60 riepiloghi/ora = 192.000 eventi/mese, prima di eventuali altri eventi. Rientra nella quota PostHog citata, ma non autorizza un piano a pagamento. Evitare carte/Blaze; in una futura scelta a consumo verificare limiti rigidi, non affidarsi solo ad avvisi di budget.

Misurare su ciascun telefono: spazio e crescita della coda, RAM/PSS, byte per UID, richieste/ripetizioni dopo riconnessione, batteria e wakeup. Prove abbinate consenso OFF/ON con stessa build, durata e stato schermo/rete, almeno tre ripetizioni da 60 minuti. Gate proposti: ≤2 MiB di crescita disco a coda piena, nessuna crescita continuativa della RAM dopo saturazione, ≤1 MiB di traffico aggiuntivo per uscita sintetica da 4 ore, regressione batteria ≤2 punti percentuali/ora con variabilità dichiarata. Differenze sotto la risoluzione della misura restano inconclusive. Il lab non avvia GNSS/BLE: anche un buon risultato richiede un successivo confronto nel runtime Convoy prima dell'adozione.

## Accessi necessari e prossimo gate

1. **Disponibile:** plugin PostHog, lettura del progetto EU 330212 e token di sola ingestione. Non serve una nuova connessione per ripetere il controllo cloud; nessuna chiave personale viene inserita nell'APK o condivisa. Progetto gratuito già verificato, senza modifiche di fatturazione.
2. **Disponibile:** toolchain Flutter 3.47.4, SDK/ADB e JDK 17. **Runtime API35 attualmente bloccato dai servizi Android**, come documentato nel follow-up. **Manca:** un telefono reale controllabile per batteria, OEM, rete cellulare e forza del segnale. L'emulatore software presenta ANR e non è una base per stime energetiche.
3. Risolvere e riprovare eliminazione della coda revocata e minimizzazione nativa nel [protocollo](../tools/telemetry_spike/README.md), mantenendo i lock e le ricevute/versioni. Successo normale: ogni ID previsto compare una sola volta; eventuali ritentativi duplicati vanno quantificati. Un timestamp server non va sottratto al clock del telefono per dichiarare latenza precisa.
4. Review indipendente prima dell'adozione. Il produttore non ha auto-approvato il kit; la review indipendente è **PENDING**.

Alternativa Firebase: progetto Spark + Analytics/GA + export Sandbox e un accesso BigQuery autorizzato; la connessione diretta qui è indisponibile. Nessuna richiesta di aggirare tale limite. Stato `PENDING` finché export e finestra di osservazione non permettono di classificare i mancanti. I filtri di traffico developer possono modificare ciò che arriva ai report/export: controllare la configurazione reale, senza basarsi su vecchie regole su DebugView. [DebugView corrente](https://firebase.google.com/docs/analytics/debugview).

## Continuità, riuso e chiusura della fase

Governance Enterprise corrente consultata con assessor e resolver in cache di sola lettura, senza modificare Enterprise. Profilo iniziale di preparazione conservato; profilo di follow-up aggiornato con `realWorldIntegration=true` per il controllo cloud, STANDARD/READY 100. Fingerprint di follow-up `04b4d0c92ffc07da11b248fe50e90e82f090ccff7f6a723f777d9cce7be7eab9`; include EP-009, prova eseguibile e review indipendente ancora pendente. Non autorizza adozione produttiva. Fingerprint pianificazione `927eb4b277be9c50a9b7d01757c9d6cabe38200f5ee4e68a221353c6e969b766`. Digest e pattern nel manifest del kit. Applicati i casi difficili richiesti da Cama: riavvio, saturazione, revoca, duplicati. Ricerca fermata al confronto dei due candidati e agli accessi verificati.

Principle 11: livello 1 per semplificare la raccolta (contatori, non log); livello 3 per riusare un SDK affidabile senza costruire un uploader produttivo; livello 5 per comporre SQLite/HTTP standard in un controllo locale riproducibile. Il codice Python non entra nell'app. Fonte del criterio: questo documento; fonte della misura: risultati JSONL/JSON e script; unico produttore della misura locale: il runner del kit. Nessun altro registry o CONTINUITY operativo creato.

Ramo di lavoro **locale**, derivato dal ramo operativo: `experiment/telemetry-minimum-infrastructure`. Nessun push, PR nuova, merge, release o modifica dell'APK esistente. La patch include l'aggiornamento del solo CONTINUITY esistente; la fonte remota non è stata aggiornata. Conservare il pacchetto fino all'eventuale autorizzazione di registrazione remota. Lo studio è revisionabile; il gate completo rimane aperto.

Ops-memory: riusate JON-2026-08-25-009/010/011 e JON-2026-09-08-001. Accesso PostHog risolto e ambiente Android preparato; limiti fisici e di esecuzione restano evidenze di questa sessione, non una nuova lezione globale. Nessun cambiamento di governance o apprendimento integrato dichiarato.
