# Contratto di studio diagnostico indipendente dall'uscita — bozza

**Decisione Cama, 14 novembre 2026:** lo studio tecnico deve poter partire, terminare e (in una fase successiva) inviare risultati senza dipendere da `Avvia uscita` / `Termina uscita`. Scopo: individuare e correggere difetti riproducibili; non raccogliere dati indiscriminatamente.

## Prima riusare, poi costruire
Primo livello sufficiente: **riuso del registratore locale esistente** `DiagnosticRecorder` e del ponte `DiagnosticCaptureBridge`, con modifica minima all'interfaccia. Il codice registra già indipendentemente dalla durata dell'uscita e salva su file privato JSONL, massimo **4 minuti**; il bridge crea snapshot ogni 5 secondi soltanto quando la registrazione è attiva. Nessun nuovo server, SDK, costo, servizio Android o dipendenza introdotti in questa fase.

**Flusso UI scelto da Cama:** non aggiungere un secondo registratore o un nuovo pulsante di registrazione. Riutilizzare l'unico controllo già presente in `Test log`, che mostra `Avvia registrazione diagnostica` quando è inattivo e `Termina registrazione diagnostica` quando è attivo. Al termine la sessione resta sul telefono, senza trasmissioni; poi offrire due azioni **facoltative e distinte**:
- **Condividi file diagnostico**: il JSONL originale viene consegnato solo al destinatario che Cama seleziona nel pannello Android; può contenere dati personali e non deve essere inviato a PostHog come log grezzo. La condivisione Android non garantisce che il destinatario sia offline o che i dati restino solo sul dispositivo.
- **Invia riepilogo a PostHog** (futuro, NON attivo): mostrare prima un'anteprima precisa dei campi ammessi, poi inviare esclusivamente un evento riassuntivo tecnico su consenso esplicito per ogni invio; niente upload continuo o implicito allo stop, e niente coordinate, tracce, nomi, ID Bluetooth o note libere.

**Vincoli correnti:** il registratore ha un limite di 4 minuti e la sua partenza richiede lo stato `Nearby` pronto nella UI; non viene avviata una uscita. Un eventuale aumento della durata non va anticipato senza misurare dimensioni, batteria e robustezza con schermo spento. L'indipendenza da `Avvia uscita` non equivale a background garantito.

`Invia ping di prova` (PR #7) è un test di connettività separato, non controlla né abilita la registrazione.

## Misure che devono orientare una modifica di Convoy
Selezionare poche metriche collegate a difetti reali:
1. **Tempo con BLE visibile e posizione peer non fresca**: frazioni di intervalli osservati in cui `online` e `fix_fresh=false`. Se mancano campioni, indicare `gap` e ridurre la copertura; non confondere visibilità con freschezza.
2. **Riaggancio dopo perdita radio**: durata osservata localmente tra perdita e nuova ricezione valida; insieme a contatori sequenza/ACK. Non usare orologi di due telefoni come se fossero sincronizzati, e non convertire RSSI in metri.
3. **Disponibilità runtime**: intervalli realmente osservati con Nearby/uscita, servizio in primo piano, pause e schermo spento; un processo ucciso non produce campioni e non può diventare un falso 100% di attività.
4. **GPS subordinato**: fix recente/vecchio, accettato/scartato, tempo di riacquisizione, accuratezza dichiarata. Non scambiare accuratezza dichiarata per errore reale; servono prove di percorso con riferimento per concludere sulla precisione.
**Guardrail:** eventi persi, coda/duplicati, deviazioni di consumo energetico, quota e privacy.

Ogni risultato deve indicare versione/build, prova, modalità, durata osservata, campioni e condizioni (fermo, passo lento, curve, perdita/ripresa, schermo spento). Per confronti fra due telefoni usare un codice sessione sintetico opzionale e condiviso volontariamente: mai nomi, ID radio o coordinate nei riepiloghi cloud. I dati dettagliati di campo rimangono privati; in CI usare solo esempi sintetici.

## Riepilogo locale — implementazione candidata (PR #8)
`DiagnosticSummary.fromJsonl` legge **soltanto localmente** il JSONL e ricava un allowlist fisso di conteggi e flag, presentato in `Test log` dopo lo stop: durata osservata, campioni runtime, campioni di peer visibili e con fix non fresco, intervalli superiori a 9 s fra snapshot nominalmente a 5 s, BLE RX accettati/scartati, TX error, fix GPS/fix freschi, record invalidi/scartati e flag di completamento. La logica utilizza solo `elapsed_ms` locale, non confronta orologi fra telefoni. Non presume di conoscere la perdita reale di pacchetti, la disponibilità continua fra campioni o la precisione GPS effettiva. Un campo zero significa *non osservato nel test*, non prova che un problema non esista.

Il riepilogo visualizza esattamente le chiavi numeriche/booleane che saranno candidate per la trasmissione futura; **non copia mai proprietà libere** dal log. Sono esclusi: coordinate, nomi, ID telefono/BLE/peer, sequenze, note, testo di errore, UTC individuale, tracciati o il JSONL originale. Test sintetici includono apposta campi privati, contenuti malformati e sessioni incomplete.

**Invio non implementato:** la UI informa che `Invia riepilogo a PostHog` non è disponibile; non mostra un pulsante fittizio e non invia nulla. Non eseguire upload o deduzioni privacy sul solo fatto che un ping manuale sia arrivato. Il progetto resta senza invio continuo per il momento.

Prima di inviare dati di studio servono, con test reali: consenso disattivato di default, revoca che ferma nuove trasmissioni e purga la coda non inviata, offline/riavvio, deduplica, limite retry, prove zero eventi revocati e politica di conservazione/cancellazione compatibile. **PR #5 è ancora HOLD** per questi gate: non bypassarli usando il ping riuscito come autorizzazione generale. Distinguere revoca del consenso futuro e cancellazione dei dati già conservati.

## Limite background Android
Indipendenza logica dalla camminata NON significa acquisizione continua garantita a schermo spento. In Nearby la scansione BLE è foreground; lo studio non diventa proprietario del servizio in primo piano né accende il GPS. Un timer Dart può fermarsi quando Android sospende/termina il processo. Non inventare parti mancanti. Solo prove reali potranno giustificare un distinto foreground service diagnostico con notifica e gestione permessi/OEM; evitare nuova complessità prima delle evidenze.

## Stato e gate
In `experiment/diagnostic-control-20261114`: interfaccia Start/Stop separata dalla condivisione file; generazione e visualizzazione di un riepilogo locale allowlisted, test sintetici su privacy e incompletezza, test emulatore aggiornato alla dicitura reale. La candidata del laboratorio ha un package separato `com.example.convoy_mesh.diaglab` e versione `0.7.7-diaglab+12`, senza sostituire Ping LAB 2. Commit sorgente app `8c9bd16ac4c6bc43fa760d25b4b5b12133d80471`, CI Android run #43652863949, risultato da confermare prima di consegna. Nessun APK ancora distribuito, nessun nuovo evento PostHog. Prossimo gate: test/build/emulatore verdi e ricevuta artefatto reale, poi prova volontaria su telefono; upload resta subordinato ai gate privacy PR #5.
