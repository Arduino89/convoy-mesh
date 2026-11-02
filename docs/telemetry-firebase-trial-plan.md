# Convoy Mesh — prova Firebase da preparare

Data: 2 novembre 2026. Stato: **PLAN_ONLY / NOT_BUILT / NOT_RUN**. Questo documento prepara un confronto con gli stessi requisiti del [laboratorio PostHog](telemetry-minimum-infrastructure.md); non autorizza attivazioni, invii, spese, modifiche a Convoy o passaggio a Firebase.

## Decisione e limiti documentati

Firebase Android espone `resetAnalyticsData()`: il contratto dichiara eliminazione dei dati Analytics locali e rinnovo dell'app-instance ID. FlutterFire espone la stessa operazione come `Future<void>`. Nessuna delle due reference consultate documenta un ACK di cancellazione durabile o una garanzia in caso di crash. Il ritorno della chiamata deve essere registrato come **RESET_CALL_RETURNED**, non come **PURGE_VERIFIED**. La cancellazione sul server è distinta. [API Android](https://firebase.google.com/docs/reference/android/com/google/firebase/analytics/FirebaseAnalytics), [API FlutterFire](https://pub.dev/documentation/firebase_analytics/latest/firebase_analytics/FirebaseAnalytics/resetAnalyticsData.html).

L'inventario pubblico consultato non offre un filtro del payload finale equivalente a `beforeSend`, un endpoint Analytics locale configurabile, un limite di coda impostabile a 32 o un contatore degli scarti. La [Local Emulator Suite](https://firebase.google.com/docs/emulator-suite) non supporta Analytics: un mock non dimostrerebbe il comportamento del SDK reale. Non sostituire il trasporto e non modificare il SDK per colmare questi limiti.

**Blocco prima del cloud:** osservazione del payload finale. **Requisito ancora da misurare:** pulizia dopo revoca e interruzione. L'assenza di un ACK SDK non rende impossibile una futura prova comportamentale con dati sintetici; impedisce di considerare la pulizia attestata dal solo ritorno dell'API. Una build riuscita, l'assenza di righe in DebugView o il cambio di app-instance ID non costituiscono una prova sufficiente.

## Gate prima di qualsiasi invio cloud

1. Scegliere un package LAB distinto da Convoy e dal laboratorio PostHog. Conservare il controllo Android indipendente, l'oracolo degli intenti e le sentinelle esistenti. Non creare o collegare progetti Firebase in questa fase.
2. Prima della prima build autorizzata, risolvere versioni esatte compatibili con Flutter 3.47.4; registrare `firebase_core`, `firebase_analytics`, dipendenze native effettive, JDK/SDK/Gradle e hash dei sorgenti. Conservare i lock Dart e Gradle e verificarli prima/dopo ogni build. **Versioni Firebase e lock non ancora risolti: nessun pin inventato in questo piano.**
3. Preparare raccolta OFF nel manifest e quattro consensi negati prima del bootstrap. Disabilitare Advertising ID e screenview automatiche. Non includere Crashlytics, Performance, Messaging, pubblicità, replay o logger applicativi. Verificare il manifest risultante dell'APK, non soltanto il template.
4. Prima di inizializzare il SDK in un futuro test diagnostico, dimostrare che l'ambiente sintetico non può inoltrare richieste ai servizi cloud. Una configurazione fittizia rifiutata dal SDK non costituisce una prova di privacy o consegna.
5. Individuare e verificare un metodo che osservi la richiesta serializzata finale del SDK, inclusi eventi automatici, header e metadati, **senza inoltrarla al cloud** e senza modificare il SDK. Conservare solo ricevute sanificate e dati sintetici ammessi, mai log diagnostici integrali. Attualmente questo metodo non è disponibile: **FINAL_WIRE_GATE_BLOCKED**.
6. Se il punto 5 non è soddisfatto, fermarsi prima di abilitare raccolta o invio verso Firebase. Non usare DebugView, BigQuery, filtri della console o una whitelist dei soli argomenti `logEvent` come sostituti del controllo finale. La prova cloud rimane NOT_RUN.

Il contratto logico applicativo ammette soltanto `schema_version`, `run_id`, `event_id`, `sequence`, `event_name`, `synthetic`, con gli stessi significati dell'oracolo PostHog. Firebase Android documenta parametri stringa/numerici: l'eventuale codifica di `synthetic=true` come intero `1` deve essere esplicita e reversibile; il normalizzatore deve rifiutare altri valori o tipi.

I campi di protocollo sono una lista separata da inventariare e motivare prima dell'invio. I due controlli PostHog `$geoip_disable` e `$process_person_profile` non diventano automaticamente parametri Firebase. App-instance ID, modello/nome del dispositivo, dati geografici, sessione ed eventi automatici non sono ammessi per il solo fatto che li aggiunga il SDK. Nomi umani, coordinate, schermo, dati del recorder e testo libero restano esclusi. La raccolta Firebase predefinita comprende dati automatici ulteriori: il consenso e i controlli della console non attestano una whitelist sul telefono. [Dati raccolti](https://support.google.com/firebase/answer/6318039?hl=en), [controlli geografici/dispositivo](https://support.google.com/analytics/answer/12002752?hl=en).

## Consenso e interruzioni: sequenza da verificare

Configurazione iniziale da controllare nel manifest risultante:

- `firebase_analytics_collection_enabled=false`;
- `google_analytics_default_allow_analytics_storage=false`;
- `google_analytics_default_allow_ad_storage=false`;
- `google_analytics_default_allow_ad_user_data=false`;
- `google_analytics_default_allow_ad_personalization_signals=false`;
- `google_analytics_adid_collection_enabled=false`;
- `google_analytics_automatic_screen_reporting_enabled=false`.

`setAnalyticsCollectionEnabled` e `setConsent` persistono fra avvii e prevalgono sui valori iniziali. In particolare, un precedente `setAnalyticsCollectionEnabled(true)` non viene annullato dal solo manifest OFF al riavvio. Un gate Dart eseguito dopo l'inizializzazione non dimostra l'assenza di invii precedenti. [Consenso Android](https://developers.google.com/tag-platform/security/guides/app-consent?consentmode=basic&platform=android), [configurazione raccolta](https://firebase.google.com/docs/analytics/android/configure-data-collection), [screenview](https://firebase.google.com/docs/analytics/screenviews).

I quattro tipi Android sono `ANALYTICS_STORAGE`, `AD_STORAGE`, `AD_USER_DATA` e `AD_PERSONALIZATION`. `setConsent` modifica soltanto le chiavi specificate: nella prova scrivere esplicitamente tutti e quattro i valori, negandoli alla revoca e concedendo soltanto Analytics al nuovo consenso. Queste impostazioni non sono una ricevuta degli eventi cancellati, un filtro di ogni campo o una garanzia sull'invio già in corso. La guida documenta la cancellazione delle proprietà utente quando viene ritirato il consenso Analytics/Ad storage, inclusa la scelta di personalizzazione: riaffermare la scelta pubblicitaria negata, senza dedurne la purga della coda degli eventi.

Il comportamento applicativo da valutare deve mantenere rifiuto e pulizia pendente persistenti; non deve riabilitare automaticamente il SDK alla ripartenza. La prova sintetica, invece, deve poter richiedere esplicitamente un nuovo consenso **per misurare** se gli eventi revocati ricompaiono. Sono due criteri distinti: nessun risultato della prova viene anticipato nel flusso applicativo.

Sequenza della futura prova, soltanto dopo il gate del payload e l'autorizzazione alla prova cloud sintetica:

1. Persistenza confermata di `consent=false` e `cleanup_in_progress=true`, prima delle chiamate SDK; blocco immediato di nuovi intenti e del nuovo consenso nel percorso applicativo ordinario.
2. `setAnalyticsCollectionEnabled(false)`, quindi `setConsent` con i quattro tipi negati.
3. `resetAnalyticsData()`; registrazione di **RESET_CALL_RETURNED / PURGE_UNVERIFIED**, senza trasformare il completamento in prova di persistenza su disco.
4. Riavvio offline, controllo del consenso, dello stato di pulizia e delle sentinelle. Verificare che il percorso applicativo ordinario non riabiliti automaticamente raccolta o consenso; non azzerare lo stato pendente perché il Future è completato.
5. Nel solo percorso diagnostico sintetico, eseguire un comando esplicito e registrato **LAB_PURGE_PROBE_RECONSENT**: concedere Analytics ancora offline, mantenere i tre consensi pubblicitari negati e generare i dieci nuovi eventi. Questo comando serve a mettere alla prova la pulizia ancora **UNVERIFIED**; non è una riabilitazione automatica o una strategia proposta per gli utenti.
6. Riconnettere e osservare l'intera finestra: verificare zero dei 20 vecchi ID, tutti i 10 nuovi, sentinelle e duplicati. La ricevuta distingue risultato comportamentale della prova e stato del requisito di adozione. Non usare `flush` per tentare di svuotare la coda revocata.

Interrompere il processo in casi separati: **prima della scrittura durabile del rifiuto**; dopo tale scrittura ma prima di SDK-disable; dopo SDK-disable ma prima del reset; immediatamente dopo il ritorno del reset. Nel primo caso la revoca non può essere dichiarata accettata o persistita prima che la scrittura sia confermata: registrare **REVOKE_NOT_COMMITTED**, senza attribuirgli un PASS o un FAIL della purga di una revoca già accettata. Registrare ordine delle azioni, PID, stesso avvio Android e sentinelle; non sostituire le osservazioni con attese temporali arbitrarie.

Dopo aver verificato il metodo di osservazione del payload e ottenuto l'autorizzazione, ripetere anche l'avvio **con rete disponibile**, predisponendo l'osservatore prima di avviare il processo. Cercare richieste del SDK prima del gate applicativo, specialmente dopo un precedente stato SDK `enabled=true` e un crash fra scrittura del rifiuto e SDK-disable. Le sole prove di riavvio offline non escludono questa corsa di inizializzazione. Gli invii precedenti al gate e lo stato durabile effettivamente raggiunto devono restare distinti nella ricevuta.

Non cancellare dati del package o file interni per far passare un caso. `cleanup_in_progress` non è un uploader o una coda sostitutiva. **Adozione ancora bloccata:** non è dimostrata una revoca affidabile; anche una futura coorte vecchi0/nuovi10 dimostrerebbe il caso e la finestra provati, non un ACK SDK o una garanzia universale. Il comando diagnostico esplicito non deve nascondere lo stato pendente né diventare un automatismo per gli utenti. La prova rimane oggi bloccata da payload/accessi, non dalla sola assenza di un ACK di purga.

## Matrice di accettazione del confronto

Le prove seguenti dipendono dai gate precedenti e dall'accesso autorizzato. Nessuna è stata eseguita con Firebase.

| Caso | Coorte e procedura | Condizione per PASS | Stato iniziale |
|---|---|---|---|
| Rifiuto | 10 tentativi iniziali, riavvio senza consenso, altri 10; ulteriori 10 dopo revoca | Nessun intento accettato o evento emesso; rifiuto persistente, sentinelle integre | NOT_RUN |
| Normale | ID 1..100 offline, force-stop, riapertura, rete | 100 ID distinti ricevuti, zero mancanti/inattesi/conflitti; duplicati contati | BLOCKED dai gate |
| Revoca | ID 101..120 offline, revoca, riavvio offline; comando diagnostico esplicito di nuovo consenso mentre la purga è UNVERIFIED, poi ID 121..130 | Zero vecchi ID in tutta la finestra; tutti i 10 nuovi ricevuti; sentinelle integre | NOT_RUN; oggi BLOCKED da payload/accessi |
| Crash durante revoca | Stesse coorti, un run per ogni punto d'interruzione, compreso prima della scrittura durabile; riavvii offline e online osservati | Prima della persistenza: REVOKE_NOT_COMMITTED, nessun PASS di revoca; dopo persistenza: rifiuto conservato, nessuna riabilitazione automatica e coorte vecchi0/nuovi10 nel probe esplicito | NOT_RUN; durabilità e adozione UNVERIFIED |
| Payload finale | Tutte le richieste ed eventi automatici della configurazione reale | Solo campi applicativi/protocollo preventivamente ammessi, prima di qualsiasi inoltro cloud | FINAL_WIRE_GATE_BLOCKED |
| Ritentativo dopo ACK perso | ID 131..140; accettazione del batch osservata, prima risposta deliberatamente persa | Ricezione/ripetizioni osservabili e riconciliate per ID; nessun duplicato eliminato dall'analisi | BLOCKED senza iniezione verificata |
| Saturazione | Run separato, prima sonda da 45 intenti; eventuale carico ulteriore con volume/durata massimi fissati prima | Tutti gli intenti conservati nell'oracolo; perdite e duplicati visibili; limite realmente osservato | NOT_RUN; cap32 non configurabile documentato |
| Risorse | Campioni prima/dopo consenso e carico, stesso processo/build | Misure con baseline e limiti dichiarati; nessuna stima del solo SDK dall'intera app debug | NOT_RUN; batteria fisica separata |

Per saturazione, 45 ricevuti su 45 non dimostrano il limite della coda: classificare **SATURATION_NOT_REACHED** se non viene raggiunto entro il budget prefissato. Non scartare 13 eventi nell'adapter per imitare PostHog. Per ACK perso, una semplice disconnessione o due chiamate applicative non provano che un batch accettato sia stato ritentato. Nessun contatore produttivo di scarto o deduplicazione cloud va dichiarato senza misura.

## Export e analisi, solo dopo autorizzazione e gate

La fonte prevista è l'export giornaliero Analytics verso BigQuery Sandbox. Preparare una query limitata al package/run e alle date della prova che conservi **una riga per evento**, senza `DISTINCT` o aggregazioni che nascondano duplicati. Verificare tipi, ID, cardinalità dei parametri, completezza/paginazione e finestra; riconciliare con l'oracolo scritto prima delle catture. Conservare il risultato completo della query sintetica e la ricevuta dei conteggi per Data.

DebugView serve al controllo operativo dopo ricezione, non alla prova di privacy. La documentazione corrente include gli eventi debug nell'export giornaliero per impostazione predefinita; registrare i filtri developer reali, che potrebbero invece escluderli. I dati giornalieri possono essere aggiornati per eventi tardivi fino a tre giorni: una finestra incompleta produce **PENDING**, non una perdita o un successo della revoca. L'assenza nella finestra completa attesta soltanto quella finestra, non una cancellazione permanente. [DebugView](https://firebase.google.com/docs/analytics/debugview), [schema e ritardi dell'export](https://support.google.com/analytics/answer/7029846?hl=en).

## Accessi mancanti e vincoli economici

| Prerequisito | Necessità concreta | Stato |
|---|---|---|
| Progetto/app di laboratorio | Firebase Spark separato, app Android registrata, Analytics e configurazione coerenti con il package LAB | Non attivato; richiede autorizzazione prima della creazione/configurazione |
| Collegamento Analytics → BigQuery | Operatore autorizzato con `firebase.links.create/update`, `serviceusage.services.enable`, `resourcemanager.projects.getIamPolicy/setIamPolicy` e Analytics Editor/Administrator sulla proprietà collegata | Non predisposto; nessuna richiesta di elevare accessi ora |
| Dataset e lettura | Dataset/date del laboratorio; `roles/bigquery.dataViewer` sulle tabelle e `roles/bigquery.jobUser` sul progetto di query, oppure export sintetico completo prodotto dal proprietario | Accesso non disponibile/verificato qui; non aggirare restrizioni del connettore |
| Osservazione prima del cloud | Metodo verificato per richiesta finale e, separatamente, iniezione dell'ACK perso | Non disponibile; l'accesso a Firebase non risolve questi blocchi |
| Toolchain e lock Firebase | Versioni esatte risolte, build riproducibile e ricevuta; nessun uso di `latest` nel campione finale | Da preparare prima della prima build autorizzata |

Spark può usare BigQuery Sandbox senza carta o account di fatturazione. I limiti documentati sono 10 GiB di storage lifetime, 1 TiB di dati processati nelle query al mese, scadenza automatica dopo 60 giorni e assenza di streaming/intraday. Verificare quote e assenza di billing prima di qualunque futura prova; nessun passaggio a Blaze, runner a pagamento o acquisto è previsto. Usare query circoscritte e una soglia esplicita di byte processabili, senza presumere che il piano gratuito elimini ogni controllo dei costi. [Export e permessi Firebase](https://firebase.google.com/docs/projects/bigquery-export), [Sandbox](https://docs.cloud.google.com/bigquery/docs/sandbox), [permessi per query](https://docs.cloud.google.com/bigquery/docs/running-queries).

**Consegna di questa fase:** solo piano revisionabile. Nessun adapter, pin Firebase, build, progetto, invio o risultato Firebase viene presentato come esistente. Un futuro kit può riusare i verificatori indipendenti già presenti; finché il gate del payload non è superato e il comportamento di revoca non è verificato, Firebase non è approvato come alternativa a Convoy.
