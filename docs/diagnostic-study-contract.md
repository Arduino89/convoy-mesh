# Convoy Mesh — diagnostica beta dettagliata (decisione e confini)

**Direzione approvata da Cama il 15 novembre 2026:** nella beta chiusa con persone conosciute, conservare nei log e **prevedere per PostHog anche** ID dispositivo/partecipante, nickname e dati GPS precisi, oltre alla sequenza degli scambi BLE. L'obiettivo è il debugging di problemi verificabili fra telefoni; il divieto precedente di questi campi nel riepilogo cloud **non è più la direzione di prodotto per la beta**. Questa decisione NON dimostra il consenso specifico di tutti i partecipanti, non autorizza invii di dati di terzi prima di informarli e non certifica l'implementazione dell'upload.

## Interfaccia e separazione dall'uscita

Riutilizzare l'unico controllo già presente nella pagina `Test log`:
- **Avvia registrazione diagnostica** — cattura localmente, senza avviare un'uscita.
- **Termina registrazione diagnostica** — ferma e conserva il log; limite attuale 4 minuti; nessun invio.
- **Condividi file (manuale)** — utilizza il pannello Android e invia il JSONL completo solo al destinatario scelto (che potrebbe essere un'app online).
- **Invia a PostHog** — **futuro pulsante separato**, con anteprima dettagliata e conferma per singola sessione; non è ancora implementato.

La schermata dà precedenza visiva al pulsante di registrazione rispetto alle spiegazioni, dopo che l'emulatore con risoluzione ridotta non riusciva a raggiungerlo. In Nearby non viene attivato GNSS/foreground service per la sola diagnostica; i fix GPS sono presenti se un componente proprietario li ha effettivamente ottenuti (per esempio l'uscita). Nessuna promessa di campionamento continuo con schermo spento o app terminata.

## Riuso e dati oggi disponibili

**Primo livello sufficiente:** riuso di `DiagnosticRecorder` e `DiagnosticCaptureBridge`, oltre alla strumentazione in `ConvoyMeshService` e `LocationFusionService`. Il JSONL locale già contiene nickname/ID di telefoni e peer, posizioni raw/display dove disponibili, accuratezza GPS dichiarata, tempi di misura/ricezione, RSSI e sequenze BLE, esiti RX/TX, HISTORY/ACK e stato del runtime. Snapshot ogni 5 s quando la registrazione è attiva; eventi BLE/GPS acquisiti alla sorgente; stop massimo a 4 minuti. Il log locale è **privato** e non deve entrare in commit, PR, artefatti pubblici o log cloud.

`DiagnosticSummary.fromJsonl` resta un **riepilogo locale aggregato**, con allowlist di numeri/booleani, utile per lettura rapida. Non sostituisce il log dettagliato e, in questa fase, non viene trasmesso. Il ping `cm_lab_ping` di PR #7 è una prova separata, riuscita su un singolo dispositivo.

## Contratto previsto per un upload beta dettagliato — non operativo

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
