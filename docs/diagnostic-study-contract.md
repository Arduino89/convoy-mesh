# Convoy Mesh — diagnostica beta dettagliata (decisione e confini)

**Direzione approvata da Cama il 15 novembre 2026:** nella beta chiusa con persone conosciute, conservare nei log e **prevedere per PostHog anche** ID dispositivo/partecipante, nickname e dati GPS precisi, oltre alla sequenza degli scambi BLE. L'obiettivo è il debugging di problemi verificabili fra telefoni; il divieto precedente di questi campi nel riepilogo cloud **non è più la direzione di prodotto per la beta**. Questa decisione NON dimostra il consenso specifico di tutti i partecipanti, non autorizza invii di dati di terzi prima di informarli e non certifica l'implementazione dell'upload.

## Interfaccia e separazione dall'uscita

Riutilizzare l'unico controllo già presente nella pagina `Test log`:
- **Avvia registrazione diagnostica** — cattura localmente, senza avviare un'uscita.
- **Termina registrazione diagnostica** — ferma e conserva il log; limite attuale 4 minuti; nessun invio.
- **Condividi file (manuale)** — utilizza il pannello Android e invia il JSONL completo solo al destinatario scelto (che potrebbe essere un'app online).
- **Invia a PostHog** — pulsante separato realizzato in PR #8 Diagnostics LAB +13, con anteprima dettagliata e conferma per singola sessione. La ricezione di una sessione reale in PostHog EU è stata osservata il 15 novembre 2026; resta aperto il gate di privacy su cancellazione/retention.

La schermata dà precedenza visiva al pulsante di registrazione rispetto alle spiegazioni, dopo che l'emulatore con risoluzione ridotta non riusciva a raggiungerlo. In Nearby non viene attivato GNSS/foreground service per la sola diagnostica; i fix GPS sono presenti se un componente proprietario li ha effettivamente ottenuti (per esempio l'uscita). Nessuna promessa di campionamento continuo con schermo spento o app terminata.

## Riuso e dati oggi disponibili

**Primo livello sufficiente:** riuso di `DiagnosticRecorder` e `DiagnosticCaptureBridge`, oltre alla strumentazione in `ConvoyMeshService` e `LocationFusionService`. Il JSONL locale già contiene nickname/ID di telefoni e peer, posizioni raw/display dove disponibili, accuratezza GPS dichiarata, tempi di misura/ricezione, RSSI e sequenze BLE, esiti RX/TX, HISTORY/ACK e stato del runtime. Snapshot ogni 5 s quando la registrazione è attiva; eventi BLE/GPS acquisiti alla sorgente; stop massimo a 4 minuti. Il log locale è **privato** e non deve entrare in commit, PR, artefatti pubblici o log cloud.

`DiagnosticSummary.fromJsonl` resta un **riepilogo locale aggregato**, con allowlist di numeri/booleani, utile per lettura rapida. Non sostituisce il log dettagliato e, in questa fase, non viene trasmesso. Il ping `cm_lab_ping` di PR #7 è una prova separata, riuscita su un singolo dispositivo.

## Contratto dell'upload beta dettagliato — implementazione sperimentale

Una **singola sessione esplicitamente selezionata** potrà produrre un flusso limitato di eventi diagnostici in PostHog EU, non un upload indiscriminato di tutto il JSONL. Conservare solo i campi necessari alla ricostruzione:
- **Identità di test:** codice sessione, dispositivo mittente, ID del peer e *nickname* quando il partecipante è consenziente. Non inferire che un nickname identifichi univocamente una persona.
- **GPS:** latitudine, longitudine, timestamp della misura e della ricezione, coordinate mostrate se presenti, accuratezza dichiarata, decisione del filtro, freschezza e buchi espliciti. Nessuna correzione alla strada; niente segmenti inventati durante perdita/riacquisizione.
- **BLE e storia:** tipo messaggio, contatore/sequence, lato TX/RX, esito, tempi di osservazione/consegna, intensità RSSI, HISTORY/ACK, cause di rifiuto predefinite. `RSSI` non è una distanza metrica.
- **Runtime:** stato app/permessi/schermo/servizio, pause, riprese e buchi di campionamento, versione dell'app/commit. Durate locali basate su monotonic clock; UTC dei dispositivi non va trattato come sincronizzato.
- **Qualità del trasferimento:** sessione incompleta, limiti e campioni scartati, conteggi di invio/consegna, ritentativi e verifica del ricevimento a server per sessione.

I dati GPS dettagliati e i nickname sono **personali o potenzialmente identificanti** anche con codici pseudonimi. Prima di ogni upload i partecipanti coinvolti devono essere chiaramente informati della destinazione PostHog EU, finalità di debug, campi raccolti, durata di conservazione, accesso e procedura di revoca/cancellazione, ed esprimere una scelta positiva. Non caricare le osservazioni di peer non consenzienti. Definire esplicitamente una procedura per identificare quali peer hanno optato in (non basta la presenza BLE). I log locali possono contenere anche osservazioni di altri peer, perciò **non usare un upload automatico del JSONL**.

**Protezione contro invii accidentali:** default OFF, anteprima di esatto contenuto/campo/peer e conferma a ogni sessione; no auto-upload al termine della registrazione; niente accodamento persistente finché il gate PR #5 non è risolto; non usare chiavi API personali nell'APK. Non includere per default testo di errori arbitrario, note libere, payload hex, token, segreti o registrazioni di terzi senza consenso. Limiti dimensionali e di frequenza prima di implementare il batching; log sintetici per i test.

**Gate PostHog:** verificare conservazione e cancellazione degli eventi nel progetto EU prima dell'invio reale di posizioni, oltre a permessi di accesso al progetto e limiti di ingestione. Una revoca impedisce nuovi invii; la cancellazione di dati già consegnati è una procedura distinta e può essere asincrona. **PR #5 è tuttora HOLD** per revoca/riavvio/coda/eventi revocati: non trasformare il ping manuale riuscito in certificazione dell'uploader. Fino a prova completata, non caricare dati personali reali su PostHog.

## Come valutare l'utilità dello studio

Risultati che devono supportare una modifica:
1. Peer BLE visibile ma coordinate non fresche: quanti campioni/quanto tempo *osservato* e quale sequenza RX, distinguendo storia e live.
2. Perdite/riagganci: intervallo monotono locale per ciascun telefono, seq mancate, ACK e buchi; gli orologi fra telefoni non sono automaticamente comparabili.
3. GNSS: differenze fra raw e display, scarti, età e accuratezza dichiarata, con percorso di riferimento indipendente per stimare l'errore reale.
4. Servizio Android: tempi osservati con schermo attivo/spento, permessi, background, arresti e riprese; assenza di campioni non equivale a perfetto funzionamento.
5. Guardrail: batteria/overhead, eventi persi, duplicati, consenso e revoca.

Confrontare prove ripetibili da fermi, a passo lento, in curva e in perdita/ripresa radio fra due telefoni che hanno acconsentito. Riporre i log originali in storage privato. Dati sintetici per repository/CI.

## Stato eseguibile e gate successivo

La PR #8 contiene già registrazione locale indipendente e il riepilogo tecnico. L'invio di dati dettagliati a PostHog **non è implementato e non è stato eseguito**. La run #43652863949 ha passato build/test/analyzer e fallito l'emulatore per controlli UI fuori viewport. La run #43653873668 ha fallito lo stesso controllo anche dopo una singola swipe; lo screenshot reale dimostra che il testo informativo spinge il pulsante sotto l'area visibile. La modifica corrente riporta il pulsante in alto, preserva le asserzioni e richiede nuovo test build/emulatore sul commit effettivo. Dopo il gate Android, prossimo lavoro: verificare il consenso e la cancellazione PostHog e progettare una preview di upload dettagliato, con nessun dato reale prima delle prove.

## Implementazione invio esplicito — PR #8 (15 novembre 2026)

Il nuovo `DetailedDiagnosticUpload.fromJsonl` crea in memoria **una singola richiesta PostHog EU /batch/** con eventi `cm_beta_diag_record`. È indipendente dal vecchio SDK/coda della PR #5: nessun avvio, stop, GPS o BLE invia automaticamente. Regole di riuso: livello 2, `DiagnosticRecorder` e i dati raccolti sono già sufficienti; livello 5, composizione con il percorso HTTPS/token pubblico di sola acquisizione già collaudato in `ManualPingService`, senza nuova dipendenza o servizio.

Solo tipi di evento elencati e campi esplicitamente approvati nel codice, incluso ID e nickname locali/peer, lat/lon raw/display e timestamp GPS, freschezza, RSSI, sequenze e ACK/HISTORY e stati Android. Testi liberi (marcatori utente, errori arbitrari, payload hex) non vengono trasferiti. La preview completa usa **gli stessi oggetti JSON** previsti dall'invio, escluso il token pubblico di progetto; oltre ai conteggi, l'interfaccia mostra tutti i peer incontrati nella sessione e richiede check individuali per dichiararne il consenso. Se anche un peer manca, l'invio è disabilitato. L'utente deve scegliere esplicitamente consenso proprio, informazione/conservazione e confermare un dialogo; l'app non può attestare autonomamente il consenso di terzi.

Solo sessioni interamente chiuse, coerenti per ID/ordine/identità, con <=1200 record e <=750000 byte possono partire; altrimenti rifiuto senza troncamento silenzioso, con file locale preservato. Una sola richiesta HTTP con `upload_id` casuale per correlare una successiva lettura indipendente su PostHog. Non esiste persist/retry; errore o timeout resta esito ambiguo e non autorizza una ripetizione inconsapevole. Il bottone si disabilita dopo un tentativo per l'intera vista; riavvio processo non garantisce idempotenza, dunque leggere `upload_id` prima di re-inviare. HTTP 2xx non è conferma di salvataggio. Revoca del consenso per invii futuri != cancellazione di eventi già conservati.

**Stato di verifica:** sorgente candidato nella PR #8; CI Flutter/Android, test sintetici del nuovo invio, progetto PostHog/retention/deletion e prova manuale sul telefono restano gate espliciti. Non caricare dati reali né inviare log privati al repository per queste prove. PR #5 resta HOLD: la nuova modalità non pretende di riparare la sua coda. Il precedente APK v0.7.7-diaglab+12 non contiene questa funzione e non va rappresentato come aggiornato.

## Contesto dichiarato dal tester — Diagnostics LAB +14 (15 novembre 2026)

**Decisione:** riuso livello 2 di `DiagnosticRecorder.record` e del JSONL esistente per associare condizioni umane alla stessa sessione, senza database, background task o dipendenze. È una nota dichiarata dal tester e **non ground truth certificato**. La registrazione conserva `session_id`, `elapsed_ms` monotono locale e timestamp UTC; gli orologi dei telefoni restano non sincronizzati e la sola scheda non valida l'accuratezza GPS.

La schermata `Test log` presenta un pannello facoltativo, chiuso inizialmente e collocato sotto il comando Start/Stop per non nasconderlo in emulatore. Il tester può dichiarare, scegliendo enum chiusi, ambiente indoor/outdoor/misto/ignoto, proprio movimento, movimento altrui **solo se osservato**, telefono in mano/tasca/zaino/appoggiato, stato dichiarato dello schermo e giudizio finale (nessun problema evidente / problema osservato / non verificato). All'avvio salva `test.context`; eventuali cambi mentre la registrazione è attiva aggiungono nuovi `test.context` con timestamp; marcatori `test.marker` a pulsante segnalano inizio/stop movimento e segnale perso/ritrovato; stop manuale aggiunge `test.outcome`. Se il timer termina automaticamente o il processo è terminato, l'esito finale può mancare: non inventarlo. Modifiche della scheda dopo lo stop riguardano solo la registrazione successiva. Note libere rimangono registrate in `user.marker` **solo localmente**.

PostHog: soltanto `test.context`, `test.marker`, `test.outcome` conformi esattamente agli enum e al campo `source=tester_declared` transitano nella allowlist dell'upload esplicito. Campi extra o valori fuori dominio fanno fallire la preparazione; mai upload automatico o copia indiscriminata di note libere. Sono inclusi nella preview e nel consenso dell'invio; il gate cancellazione/retention degli eventi personali è ancora aperto. **Nessuna prova su telefoni reali di +14** finché APK/build/emulatore e revisione non superano il gate. PR #8 resta draft, nessun merge o release.

### Review UX preliminare, senza cambio di navigazione

Le attuali tre sezioni Radar BLE / Mappa / Test log sono funzionali ma tecnicamente dense: il tema Material 3 usa un seed blue-grey, i controlli sono distribuiti in Card e le diagnostiche appaiono allo stesso livello delle azioni quotidiane. Proposta per una fase separata: uno stato leggibile Vicini/Posizione recente/Posizione vecchia, CTA di uscita facilmente raggiungibile, mappa protagonista, diagnostica a percorso guidato, dettaglio radio avanzato collassabile, contrasto/accessibilità anche all'aperto. Nessun refactor di BLE/GPS o navigazione in questa fase; validare prima su schermi piccoli e prova accessibilità.

## Outdoor LAB +17 — closed beta readback gate (19 novembre 2026)

Decisione Cama: riattivare la trasmissione diagnostica dettagliata esplicita nella beta chiusa Outdoor, senza attendere la gestione avanzata della cancellazione/retention. Questa eccezione limitata non certifica la privacy, non toglie il consenso individuale, non autorizza upload automatici né estende l'accesso al pubblico. Informare i partecipanti anche dell'analisi tramite ChatGPT e della cancellazione/retention non ancora verificate; non inviare se manca un consenso. Il coordinatore beta riceve richieste riferite a upload_id; non promettere cancellazione già verificata. PR #5 e i suoi budget/limiti restano distinti e invariati.

Nel terminale `session.stop` si aggiungono `upload_record_count` e `upload_excluded_count`: contano il batch effettivamente preparato e i record esclusi dall'allowlist, non certificano consegna. Verificare count, indici unici, inizio/fine, scarto rispetto al manifest, e valori attesi. Indici non consecutivi possono essere normali per esclusioni esplicite; zero duplicati non prova zero perdite. HTTP 2xx non prova storage. La CI invia una sola richiesta sintetica (7 record, 1 esclusione) sul nuovo checkpoint, nessun telefono/utente reale, senza retry; l'artefatto `convoy-synthetic-cloud-expected` contiene solo il manifest sintetico privo di token. L'esatta lettura PostHog tramite ChatGPT rimane gate separato. Per sessioni reali si confrontano conteggi/indici e, quando disponibile privatamente, l'anteprima originale per integrità di ogni campo. Nessun dato di posizione reale in GitHub.
