# Telemetry spike — istruzioni riproducibili

**Mandato corrente del 2 novembre — invio diretto:** autorizzato esclusivamente nel laboratorio un componente Android senza SDK analytics, verso il ricevitore locale con credenziale fittizia. È un'eccezione esplicita al precedente divieto di sender proprio, non un'integrazione Convoy. Il workflow dedicato esegue ora il controllo Android indipendente e, soltanto dopo, costruisce/esegue il [prototipo diretto](direct_trial/README.md). Riusa SQLite e HTTP di Android, osservatore del contenuto e controlli esistenti. Il contratto resta invariato, altri SDK sospesi. Risultati e commit esatto sono nel [rapporto corrente](../../docs/telemetry-minimum-infrastructure.md); una build o i test Python non attestano Android.

**Eseguito:** sorgente `89b3a35d3a55c86d60a1cb5b779cfeba7fd00776`, run `41521892190`/job `125539742017`, tentativo1 SUCCESS. Revoca completata e tre interruzioni dopo il suo salvataggio: in ogni caso vecchi0/20, nuovi10/10 e sentinelle conservate. Prima del primo commit recuperati20 eventi: confine osservato, non revoca accettata. Rifiuto, consegna100, contenuto, ritentativi e saturazione verificati nel LAB;94 controlli host separati. [Ricevute](../../docs/telemetry-evidence/2026-11-02/run-41521892190/direct-public/result.json). Nessun invio cloud o via libera all'app.

Per ricontrollare le ricevute con il verificatore indipendente, dalla radice del repository (non esegue Android):

```sh
python3 docs/telemetry-evidence/2026-11-02/direct-review-41521892190/recompute_direct_review.py \
  docs/telemetry-evidence/2026-11-02/run-41521892190 \
  --support docs/telemetry-evidence/2026-11-02/direct-review-41521892190 \
  --out /tmp/convoy-direct-independent-review.json
```

Il risultato coincide con la ricevuta indipendente pubblicata, SHA-256 `7da09ec6c8c28ae5013b207eed6fdfdd0de967f110b796165d381411af5c63d5`. Il bundle runtime rimane integro e separato dai file della revisione.

**Checkpoint precedente — Mixpanel:** precheck sulle fonti Flutter 3.1.0/Android 8.11.1 concluso con **PRECHECK_BLOCKED_MINIMIZATION**: API di cancellazione ed endpoint iniziale disponibili, ma metadati di sessione ed evento di nuovo consenso non eliminabili tramite il percorso pubblico esaminato. Tutte le prove Mixpanel sono **NOT_RUN**. Il vecchio campione PostHog sottostante è conservato a fini di riproducibilità storica e non va rilanciato invariato come correttivo. [Causa, fonti e limiti](../../docs/telemetry-minimum-infrastructure.md).

**Diagnosi successiva del 2 novembre:** nelle versioni effettivamente provate `reset` conserva la coda per contratto; `close` può tentare un invio e non è una purga. Nessuna API supportata di cancellazione mirata trovata. Il codice e le prove riportate sotto restano invariati, con revoca fallita; non rieseguire la stessa combinazione come tentativo di correzione. La sicurezza in caso d’interruzione durante la revoca è **NOT_RUN**. Causa e riferimenti nel [rapporto corrente](../../docs/telemetry-minimum-infrastructure.md); [passo minimo Firebase](../../docs/telemetry-firebase-trial-plan.md), senza build o attivazioni.

**Ciclo GitHub autorizzato del 2 novembre:** laboratorio sul ramo `experiment/telemetry-runtime-lab`, [PR #5 in bozza](https://github.com/Arduino89/convoy-mesh/pull/5). Il controllo Android indipendente è passato realmente nel run `41427231262`. Il ciclo SDK `41429419307`/job `125223965237`, sorgente `764bc41080c7b85d25ea895ed16c4b94130c5822`, è concluso: Android e build PASS, consegna100/100, contenuto finale conforme, nuovi10/10; **revoca FAIL: tutti i20 vecchi ID riappaiono**. ACK perso:20 righe/10 ID con UUID conservati; saturazione:32/45, primi13 mancanti rilevati. Tracce e impostazioni sintetiche conservate. Il job è correttamente rosso e l’adozione resta bloccata. Stato, ricevute e limiti nel [rapporto corrente](../../docs/telemetry-minimum-infrastructure.md). La suite host passa 77/77: questi test non sostituiscono Android.

**Correzione del verificatore:** `distinct_id` accetta soltanto il run esatto; due regressioni falliscono prima della correzione e passano dopo, compreso il controllo HTTP e la redazione dell’ID estraneo. Il campo `uuid` dell’evento resta indipendente. Il checkpoint locale precedente aveva 56/56 controlli e nessuna nuova prova Android; è storico rispetto al ciclo GitHub riportato sopra.

**Stato storico del follow-up del 1 novembre:** candidato con filtro nativo e controprova `resetClose` compilato e analizzato; 40/40 controlli Python passati. **Nuove prove SDK NOT_RUN:** i servizi Android dell’emulatore falliscono prima dell’esecuzione del laboratorio. Nessuna nuova conferma di eliminazione della coda o minimizzazione finale. I comandi in fondo sono il protocollo da eseguire su un runtime stabile.

**Risultati del ciclo precedente:** 25 controlli Python passati; APK Android del laboratorio compilata e installata nell'emulatore; controllo cloud reale riconciliato 10/10. Il percorso SDK Android offline → riavvio del processo → cloud è verificato: 100/100 ID, nessun mancato o duplicato anche dopo due flush aggiuntivi. **Revoca fallita:** 20/20 eventi revocati ricompaiono alla riadesione. Saturazione verificata: coda 32, 45 richieste, ricevuti gli ultimi32. Metadati nativi da minimizzare e risorse fisiche da misurare; adozione bloccata. Decisione e risultati: [rapporto](../../docs/telemetry-minimum-infrastructure.md). Questa cartella non è importata dall'app e non aggiunge servizi permanenti o account; il ciclo successivo autorizzato usa il solo workflow dedicato.

## Esecuzione autorizzata su GitHub

Il ramo dedicato `experiment/telemetry-runtime-lab` pubblica soltanto il laboratorio e `.github/workflows/telemetry-runtime-control.yml`. Il primo job esegue la piccola app di controllo, prima di qualsiasi prova SDK. La bozza conservata sotto tools è storica; il workflow attivo è quello dedicato in .github. Nessuna modifica dell’app Convoy, merge o release. Il contesto senza pubblicazione descritto più sotto appartiene alla fase precedente all’autorizzazione.

`run_ci_lab.sh` richiede il controllo sullo stesso avvio Android, compila due APK con `ci_build_trial.py` e avvia `ci_native_trial.py`. Le APK precedenti erano assenti: nessun riuso non dimostrato. Sono fissati Flutter 3.47.4/Dart 3.13.3, JDK17, platform36/build-tools36.0.0 e i lock Dart/Gradle. La build debug mantiene tutte le ABI previste dai lock e seleziona l'APK x86_64 verificata per l'emulatore API35. La ricevuta registra commit, hash dei sorgenti/lock/APK, firma e versioni native effettivamente risolte.

Il ricevitore locale viene avviato prima dell'installazione. Rifiuto, riavvio del processo, revoca/nuovo consenso, sentinelle rilette dallo storage, richiesta finale, ACK perso e coda32 hanno oracoli separati. La revoca cerca i vecchi ID anche nel ricevitore della successiva prova retry. `pm clear` riguarda solo il LAB fra casi indipendenti, mai la revoca. Errori dell'ambiente bloccano i test dipendenti; un requisito fallito resta FAILED e non cambia gli attesi.

Il runner standard pubblico non usa upload-artifact o cache Actions. `emit_ci_evidence.py` ammette soltanto JSON/JSONL enumerati, rifiuta chiavi duplicate e credenziali, riserializza i valori verificati e produce nei log un bundle sintetico con SHA-256. Nessun APK, token, URL debugger o log diagnostico integrale viene esportato. Il percorso di questo ciclo è il SDK nativo verso il ricevitore locale, senza nuove richieste a PostHog Cloud; le prove cloud storiche rimangono distinte.

## Riprodurre i controlli locali

Il riferimento richiede solo Python 3.10+ con sqlite3. Il laboratorio Android richiede Flutter 3.47.4, SDK/ADB e JDK 17 completo di `javac`/`jlink`. In questo ambiente i launcher Java mancanti sono stati ricostruiti dai moduli già presenti, senza cambiare il Java di sistema. Esportare `CI=true BOT=true` e soppressione analytics nei comandi Flutter; il preparatore lo fa nei propri subprocess. Usare il proxy/CA gestito anche per Gradle. Dalla radice del repository:

```sh
python3 -m unittest discover -s tools/telemetry_spike -p 'test_*.py' -v
python3 tools/telemetry_spike/probe.py lab --out /tmp/convoy-telemetry-new-run
python3 tools/telemetry_spike/probe.py reconcile --expected /tmp/convoy-telemetry-new-run/restart/expected.jsonl --received /tmp/convoy-telemetry-new-run/restart/received.jsonl
```

Usare una directory di output nuova: il runner non sovrascrive prove precedenti. Tutti i dati sono sintetici. Il ricevitore è temporaneo e ascolta solo su loopback. Un processo differente per ogni fase legge lo stesso database; uscita brusca dopo commit, nessuna garanzia sul kill nel mezzo di una scrittura. `results.json` contiene PID, contatori, risorse e stato di ciascuna fase. Gli input attesi sono conservati separatamente dal database: ciò che la coda perde resta rilevabile. Nessun valore di questi risultati misura un SDK o un telefono.

L'analisi usa l'insieme completo degli ID attesi, l'insieme ricevuto e il numero di righe. Un conteggio totale uguale non basta. La quota ricevuta è `ID attesi presenti / ID attesi`, non la percentuale di righe; se il denominatore è zero, la quota è indefinita. Rifiutati e revocati devono produrre zero record, senza essere classificati come perdita di consegna. Ogni export di provider deve essere completo nella finestra dichiarata, recente e riferito al run esatto.

## Preparare l'app isolata PostHog

Prima: progetto di prova EU gratuito e collegamento di lettura disponibili, privacy settings verificati, nessun dato reale. Build e installazione eseguite per la variante con ricevitore locale. Il progetto EU 330212 è collegato per il controllo API; usare la configurazione corretta per distinguere i due percorsi.

```sh
python3 tools/telemetry_spike/posthog_trial/prepare_trial.py --check-env
python3 tools/telemetry_spike/posthog_trial/prepare_trial.py --out /tmp/convoy-telemetry-android
cd /tmp/convoy-telemetry-android
flutter pub get --enforce-lockfile
cd android
./gradlew :app:dependencies --configuration debugRuntimeClasspath
./gradlew :app:dependencyInsight --dependency com.posthog --configuration debugRuntimeClasspath
cd ..
```

Il preparatore copia i lock verificati inclusi in `posthog_trial/locks/`. Conservare `pubspec.lock`, `android/app/gradle.lockfile` e l'albero delle dipendenze nella ricevuta privata; verificare versioni effettive di `posthog-android` e `posthog` e ripetere la risoluzione senza cambi prima del test. Il pin Dart da solo non blocca i range Gradle. Non aggiungere i lock del lab all'app Convoy. Sorgente API ispezionato: PostHog commit `5d8eaaa8c68612f345f945d44a9c88c8315286aa`, package 5.58.3; risolti e compilati `posthog-android` 3.75.0 e core `posthog` 6.48.0. I lock debug comprendono le tre ABI della build universale: non passare a una singola ABI senza risolvere e registrare consapevolmente un nuovo lock.

Preparare fuori dal repository un file privato `lab.local.json` con `POSTHOG_PROJECT_TOKEN` (solo token pubblico di ingestione), `POSTHOG_HOST` pari all'host EU verificato `https://eu.i.posthog.com`, `LAB_RUN_ID` univoco nella forma `synthetic-posthog-restart-001`, `LAB_QUEUE_SIZE` pari a 1000 e `BUILD_COMMIT` pari al commit effettivamente compilato. Non includere chiavi personali di query. Poi:

```sh
flutter analyze
flutter build apk --debug --dart-define-from-file=/private/path/lab.local.json
```

Non pubblicare. In questo incarico è autorizzata l'installazione del solo laboratorio sull'emulatore isolato; ogni uso su telefoni reali o utenti richiede un perimetro distinto. Prima di consegnare/avviare l'APK registrare commit, comando, package, versione/build, dimensione, SHA-256 e certificato (`apksigner verify --print-certs`). Il package deve essere `com.cama.telemetry.convoy_telemetry_lab`, versione 0.0.1+1 nella build universale (versionCode 4001 nella variante x86_64 `--split-per-abi` del follow-up), distinto dalle due app Convoy. Nessuna disinstallazione di Convoy. La firma debug non garantisce aggiornamenti compatibili.

L'interfaccia presenta solo pulsanti di test e una ricevuta copiabile. Lo stato locale condiviso via preferences aiuta la ripartenza, ma non costituisce garanzia di persistenza dopo un crash: l'oracolo atteso va creato e conservato sul computer prima di interrompere l'app. Non desumere ricezione dal ritorno di `capture()` o `flush()`.

## Sequenza Android → PostHog → Data

Per ogni scenario usare un run ID distinto e una installazione lab pulita. Pulire solo il package LAB dopo avere salvato le prove, mai le app Convoy. Non cambiare run mantenendo una vecchia coda. Prima del primo consenso controllare assenza di eventi/richieste SDK: l'AUTO_INIT è disabilitato nel Manifest generato.

1. **Rifiuto:** avviare senza consentire; premere genera 10. Chiudere/riaprire e ripetere. Nessun evento `cm_lab_probe`, nessun contatto SDK. Provare anche rete già disponibile all'avvio. Attenzione: zero eventi nel backend da solo non prova zero traffico.
2. **Percorso normale:** consenso attivo, rete del telefono disabilitata (Wi-Fi e dati mobili). Generare 100 eventi con coda 1000. Conservare ricevuta e attesi 1..100; chiudere il processo, riaprire ancora offline; ripristinare rete e richiedere invio. Query PostHog dopo la riconnessione: 100 ID unici previsti, zero mancanti/inattesi/duplicati. Rilevare a 0/1/5/15 minuti senza polling continuo. Se il servizio è indisponibile il risultato è `BLOCKED`, non perdita dimostrata. Superata la finestra, classificare gli ID non osservati come mancanti entro la finestra, non perduti per sempre.
3. **Durabilità:** ripetere separatamente kill subito dopo richiesta, kill dopo 2 secondi, riavvio Android e force-stop seguito da apertura esplicita. Distinguere i casi. Non promettere invio mentre Android mantiene l'app force-stopped.
4. **Saturazione:** build identica salvo coda 32 e nuovo run. Offline generare 45; riavvio e riconnessione. La documentazione suggerisce conservazione degli ultimi 32; controllare gli ID, non assumere l'esito. Rilevare esattamente i mancanti. A coda 1000, una seconda prova 1010 verifica il limite previsto. Il laboratorio Python non dimostra che il SDK esponga un contatore degli scarti.
5. **Revoca:** offline, consenso attivo, generare 20 (due pressioni da 10); revocare, riavviare, ripristinare rete e tentare invio. Zero eventi successivi alla revoca. Riattivare consenso in una fase esplicita e cercare i 20 ID vecchi: se compaiono, il requisito di eliminazione non è superato. Conservare separati eventi già ricevuti prima della revoca. Ripetere revoca durante invio e dichiarare l'eventuale intervallo di richieste già in volo.
6. **Duplicati:** ripetere flush/reconnect senza generare nuovi ID; confrontare righe e unici. Una caduta di rete non garantisce che sia avvenuta dopo l'accettazione server: tale caso resta non dimostrato se manca una ricevuta di quel punto. Il controllo locale con conferma fallita è solo un controesempio per l'analizzatore.
7. **Privacy:** ispezionare privatamente payload effettivo e proprietà memorizzate, inclusi metadati aggiunti dal SDK, GeoIP, IP, ID persistenti ed eventi automatici; non caricare packet capture o log completi. Nel kit usare soltanto il risultato sintetico normalizzato. Un filtro Dart non vede tutte le aggiunte native.
8. **Data:** tramite connessione PostHog leggere il progetto giusto ed eseguire le query di `queries.sql` per il run. Conservare ID/query, orario, finestra, risposta completa e fonte. Confrontare con gli attesi usando `probe.py reconcile`; mantenere tutte le righe, non pre-deduplicare. Un eventuale export manuale dimostra l'analisi sull'export, non il collegamento automatico. Il controllo `synthetic-cloud-control-001` ha eseguito questa lettura reale: 10 righe, 10 unici, nessun mancato o duplicato. È un controllo API, non la prova offline del telefono.

Per generare l'oracolo sintetico sul computer, dalla cartella del kit:

```sh
python3 - <<'PY'
from pathlib import Path
from probe import event, write_jsonl
write_jsonl(Path('expected.jsonl'), [event('synthetic-posthog-restart-001', i) for i in range(1, 101)])
PY
```

## Ricevitore locale e controllo cloud: riproduzione distinta

Per la build locale il file privato contiene `LAB_LOCAL_RECEIVER=true`, `LAB_RUN_ID=synthetic-native-restart-001`, `LAB_QUEUE_SIZE=1000` e `BUILD_COMMIT` effettivo. Non fornire token reali: il codice li rifiuta in modalità locale. Il solo token ammesso è quello fittizio incorporato. Il ricevitore salva sei campi normalizzati, nomi delle proprietà aggiunte e byte del corpo, mai il payload diagnostico completo:

```sh
python3 tools/telemetry_spike/native_receiver.py --out /tmp/convoy-sdk-receiver-new
```

Il processo ascolta su `127.0.0.1:8765`; l'emulatore usa `10.0.2.2:8765`. Devono condividere lo stesso namespace di rete. `--fail-first-ack` salva il primo batch e risponde 503: serve a misurare duplicati del SDK, non imita la deduplicazione del servizio PostHog. L'assenza di questo ricevitore è un endpoint irraggiungibile, non prova della disattivazione della radio.

`android_lab_control.py` controlla soltanto il package LAB: `inspect`, `tap --label 'Genera 100 eventi'`, `status`, `stop`, `launch`. Le coordinate sono ricavate dalla UI corrente; uno snapshot fallito non può essere riutilizzato. Lo stato preferences è intenzione di invio, non ricevuta SDK. `launch --software-rendering` usa i flag ufficiali Flutter per ambienti senza GPU adatta. Salvare le ricevute di ogni fase e il cambio di PID prima/dopo force-stop.

Per il controllo **API cloud**, con oracolo già preparato e file privato contenente `project_id`, `POSTHOG_PROJECT_TOKEN`, `POSTHOG_HOST`:

```sh
python3 tools/telemetry_spike/cloud_probe.py --config /private/path/posthog.json --project-id 330212 --input /private/path/expected.jsonl --out /tmp/convoy-cloud-new
```

Una sola chiamata esplicita, 1..1000 record validati, nessun retry automatico. Se il risultato è incerto, interrogare prima di reinviare. Ogni chiamata genera nuovi UUID; non usare questo controllo per inferire deduplicazione del SDK. Eseguire la query esatta del run tramite PostHog e conservarne risposta/finestra/orario/progetto. Per normalizzarla senza deduplicare:

```sh
python3 tools/telemetry_spike/query_receipt.py --input /private/path/query-result.json --out /tmp/received-new.jsonl
python3 tools/telemetry_spike/probe.py reconcile --expected /private/path/expected.jsonl --received /tmp/received-new.jsonl
```

La query a 500 righe è adatta ai casi piccoli; se raggiunge il limite, fermarsi e paginare esplicitamente. Non considerare un export parziale come assenza di eventi. Query privacy distinta: `$geoip_disable` vero, zero `$ip`/città/latitudine/longitudine. La presenza di proprietà native ulteriori va valutata sul SDK; il successo del payload Python non le esclude.

### Controllo Android senza UI e proxy gestito

La variante debug dal commit `02034a0` espone `ext.convoyTelemetryLab.control` soltanto quando `kDebugMode` è vero. `android_vm_control.py` scopre esclusivamente il servizio del PID del package LAB e invoca gli stessi `_action` dei pulsanti. Non modifica memoria interna del SDK o preferences. Richiede il run esatto e blocca richieste concorrenti; non è una prova dell'interfaccia o della build release. La connessione debugger con il codice di autenticazione va conservata in un file privato escluso dalle prove.

```sh
python3 tools/telemetry_spike/android_vm_control.py connect --run-id synthetic-android-cloud-001 --connection /private/path/debug.json --receipt /private/path/actions.jsonl
python3 tools/telemetry_spike/android_vm_control.py status --run-id synthetic-android-cloud-001 --connection /private/path/debug.json --receipt /private/path/actions.jsonl
```

Azioni ammesse: `grant`, `revoke`, `generate10`, `generate45`, `generate100`, `flush`, `status`. Dopo ogni nuovo processo eseguire `connect`. Se una chiamata va in timeout, leggere stato e backend prima di ripeterla: il timeout non attesta mancata esecuzione.

`android_environment.py` accetta solo un seriale `emulator-*` e registra `offline`, `online`, `managed-proxy`, `sample`. Le azioni offline disabilitano Wi-Fi/dati e abilitano modalità aereo; verificare i valori e l'assenza di rete predefinita nella ricevuta. I campioni contengono solo PSS/RSS e dimensione totale dei dati LAB, non dump completi né dati di altri package.

In ambiente con proxy TLS gestito: `prepare_trial.py --debug-ca /path/public-ca.pem` include solo il certificato pubblico come ancora di fiducia **debug-only**. Mai chiavi private o trust-all. Il controllo `managed-proxy` instrada il guest attraverso il proxy già configurato per la sessione. Non serve su un telefono con normale connessione HTTPS; non estendere questa configurazione all'app Convoy.

## Firebase, se serve il confronto pratico

Progetto Spark isolato, app con package distinto, niente Blaze. Aggiungere solo Firebase Core/Analytics al lab e usare gli stessi ID e quantità. Configurare `firebase_analytics_collection_enabled=false`, `google_analytics_adid_collection_enabled=false`, personalizzazione pubblicitaria disabilitata e consenso coerente prima dell'avvio. Bloccare e registrare le versioni FlutterFire/native risolte prima di eseguire: nessuna combinazione è certificata da questa consegna.

Ripetere il protocollo con `setAnalyticsCollectionEnabled`, `setConsent` e `resetAnalyticsData`, verificando la persistenza del rifiuto, coda residua e identità. Eventi custom con `synthetic=1`; i nomi di parametro sono gli stessi. Non assumere di poter chiamare un flush o imporre un limite di coda equivalente a PostHog.

Collegare export Analytics → BigQuery Sandbox in regione scelta prima della creazione. Non combinare tabelle intraday e giornaliere. Per la riconciliazione registrare completamento/freschezza export e ripetere entro una finestra massima di 72 ore; non lasciare un processo in attesa qui e non creare una nuova automazione. Prima della chiusura finestra i mancanti sono `PENDING`. Controllare filtri developer e modalità debug nella configurazione corrente. Query preparata in `queries.sql`; il collegamento BigQuery in questo account resta disabilitato, non aggirarlo.

## Memoria, traffico, batteria: campioni emulatore e protocollo fisico pendente

Registrare modello/API/build, stato schermo, rete, temperatura, livello batteria e durata. Eseguire sessioni abbinate OFF/ON sullo stesso telefono, almeno tre coppie da 60 minuti, alternando l'ordine. Prima test idle lab, poi il futuro runtime integrato con identico stimolo pedonale. Non confrontare telefoni diversi come se fossero equivalenti.

`adb shell dumpsys meminfo com.cama.telemetry.convoy_telemetry_lab` permette campioni RAM/PSS. Misurare privatamente file SDK e contatori byte dell'UID del solo lab; `dumpsys batterystats` fornisce stime, non energia certificata. Eventuali dump globali restano privati e vanno minimizzati prima di condividerli. Non attivare root, VPN, proxy esterni o profiling a pagamento. Gli eventuali proxy e CA dell'ambiente gestito vanno rispettati senza disabilitare TLS.

`android_network_sample.py --out /private/path/new-network-sample.json` legge solo la cronologia NetworkStats del UID LAB e salva contatori normalizzati; non salva il dump completo. Il campione è cumulativo e può essere arretrato rispetto all’ultimo invio, senza baseline: non equivale al costo del solo SDK.

Confrontare coda vuota/piena e plateau dopo ulteriori inserimenti; contare retries, wakeup e byte durante un periodo offline. Raccogliere energia con strumenti adatti se le percentuali batteria non risolvono il delta. Nessun `flushAt=1` come impostazione produttiva. Le soglie proposte sono nel rapporto; se il metodo non le distingue, dichiarare `INCONCLUSIVE`.

## Criterio di uscita

Il gate è superato solo con raccolta sintetica reale Android, riconciliazione nel backend, lettura Data, controlli di consenso/privacy e misure di risorse completati e revisionati. Un PASS locale, una build o un log di invio non bastano. In caso di fallimento conservare le prove private, fermare l'adozione e correggere nel lab. Nessun merge, pubblicazione o utilizzo su utenti reali è autorizzato dal kit.


## Follow-up locale: API native e payload finale

Il nuovo percorso `LAB_NATIVE_FILTER=true` è riservato al ricevitore locale e al token fittizio. Usa `PostHogAndroidConfig.addBeforeSend` prima di `PostHogAndroid.setup` e mantiene il trasporto/coda ufficiali. Le chiamate passano da un piccolo MethodChannel Android; non è una correzione del pacchetto Flutter upstream, un fork del SDK o un uploader proprio. Il valore predefinito conserva il percorso Flutter precedente.

`LAB_REVOKE_MODE=resetClose` prova `optOut → reset → optOut → close` e **non dichiara che questa sequenza elimini la coda**. La prova deve dimostrarlo con eventi vecchi/nuovi distinti. Nessuna cancellazione dei file interni del SDK o dati dell’app. Preferenze/file sentinella sono dati sintetici indipendenti dalla telemetria. `action_ok=false` interrompe il test e disattiva la raccolta.

Preparare un nuovo progetto con `posthog_trial/prepare_trial.py`, riusando Flutter 3.47.4 e i lock. Configurazione locale senza credenziali:

```json
{"LAB_LOCAL_RECEIVER":true,"LAB_NATIVE_FILTER":true,"LAB_REVOKE_MODE":"resetClose","LAB_RUN_ID":"synthetic-native-review-001","LAB_QUEUE_SIZE":1000,"BUILD_COMMIT":"<commit-effettivo>"}
```

Compilare con `flutter build apk --debug --no-pub --split-per-abi --dart-define-from-file=lab.private.json`. La variante x86_64 generata da Flutter ha versionCode 4001 (0.0.1); resta il solo package LAB. Verificare hash/firma e registrare il commit. I telefoni non sono parte di questa prova.

Il ricevitore e ADB devono essere nel namespace dell’emulatore. Il proxy gestito va preservato per destinazioni esterne, con esclusione del solo host locale `10.0.2.2` per il ricevitore. Non configurare token reali in questa variante.

```sh
python3 tools/telemetry_spike/wire_audit_receiver.py --out /tmp/convoy-native-followup/wire-normal --run-id synthetic-native-review-001
python3 tools/telemetry_spike/run_native_followup.py normal --run-id synthetic-native-review-001 --out /tmp/convoy-native-followup/normal --wire /tmp/convoy-native-followup/wire-normal --runtime-gate /tmp/runtime-control-smoke/receipt.json
python3 tools/telemetry_spike/run_native_followup.py revoke --run-id synthetic-native-review-001 --out /tmp/convoy-native-followup/revoke --wire /tmp/convoy-native-followup/wire-normal --runtime-gate /tmp/runtime-control-smoke/receipt.json
```

Ogni fase richiede `--runtime-gate` dalla prova indipendente su questo emulatore e questo avvio Android: una ricevuta vecchia, fallita o di un altro dispositivo blocca il runner. Il controllo precede installazione/avvio del LAB. La prima fase richiede installazione LAB pulita e consenso falso. Il runner non installa, non esegue `pm clear` e non cancella storage. Conferma rete disponibile durante il rifiuto, assenza della rete durante cattura/riavvio, PID cambiato e sentinelle. Registra l’oracolo prima delle catture. Nella revoca il nuovo consenso e i 10 nuovi ID avvengono **ancora offline**, prima della riconnessione.

Per il ritentativo, dopo il drenaggio fermare il ricevitore e riavviarlo con una nuova cartella, stesso run e `--ack-mode close-first`; eseguire la fase `retry` usando quella cartella. Il primo batch viene salvato e sincronizzato, poi la connessione chiusa senza risposta. Conservare UUID e tutte le righe; non confondere questa prova con la deduplicazione cloud. `503-first` è una controprova distinta.

Per saturazione compilare stessa sorgente con run `synthetic-native-overflow-002` e coda 32. Isolare la nuova installazione LAB **prima** della prova, avviare ricevitore nuovo e fase `overflow`. L’oracolo deve mantenere tutti i 45 ID; i 13 persi non vanno eliminati dal denominatore.

`requests.jsonl` controlla percorso, header, struttura dell’intero batch e proprietà finali, anche per richieste/eventi inattesi. Valori sconosciuti sono oscurati, chiavi e violazioni restano visibili. `received.jsonl` conserva duplicati. HTTP200 del ricevitore non significa privacy PASS. Nessun dato viene inoltrato a PostHog. `summarize_followup.py EVIDENCE_ROOT` ricalcola ricevuti/mancanti/duplicati e UUID ripetuti; fasi assenti restano NOT_RUN_OR_INCOMPLETE.

Questi comandi sono istruzioni riproducibili; soltanto le ricevute e il rapporto attestano quali fasi sono state davvero eseguite. Un’assenza di eventi per pochi secondi non è garanzia di purga permanente. Batteria, OEM e interruzione durante scrittura/revoca restano prove distinte.

## Accesso al runtime: proposta inattiva

`github-runtime-control.proposed.yml` è una bozza fuori da `.github/workflows`: non esegue nulla. Riusa il tipo di runner GitHub con KVM già collaudato dal progetto, costruisce soltanto la piccola app nativa e conserva due ricevute limitate, senza APK o log di sistema. Per attivarla occorre pubblicare il codice del laboratorio e il nuovo workflow su un ramo dedicato; non è stato fatto nel perimetro senza pubblicazione. Il flusso Convoy esistente resta identico.

La bozza esegue soltanto il controllo preliminare Android. Anche un suo futuro successo non varrebbe come test del SDK: le prove di telemetria devono seguire, sullo stesso emulatore che supera nuovamente il controllo, con le dipendenze fissate e le ricevute del laboratorio. Prima del nuovo controllo la ricevuta è assente, quindi nessuna fase nativa è autorizzata a partire dal runner locale del kit.
