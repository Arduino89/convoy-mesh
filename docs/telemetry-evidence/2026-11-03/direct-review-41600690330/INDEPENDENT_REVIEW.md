# Revisione indipendente — regressione Android locale

**Esito: regressione locale confermata; cloud `NOT_RUN`.** Revisione delle ricevute del [run 41600690330](https://github.com/Arduino89/convoy-mesh/actions/runs/41600690330), sorgente `2d76100fda1df0637e953f4ad90f26073028880c`. Questa revisione non ha avviato un altro Android né inviato dati.

Ricalcolati i risultati dai payload finali e dagli stati nativi, senza importare il classificatore del laboratorio. Verificati 107 hash del bundle e 18 file del commit pubblicato. Le ricevute originali di controllo/build corrispondono ai riferimenti e, semanticamente, alle copie normalizzate.

| Prova | Risultato osservato |
|---|---|
| Consegna normale con riavvio offline | 100/100, nessun duplicato |
| Revoca completata e tre interruzioni dopo commit | 0 degli 80 revocati ricevuti; tutti i 40 nuovi ricevuti |
| Rifiuto iniziale e dopo revoca | 0/30 ricevuti |
| Risposta persa nel receiver locale | 20 righe, 10 ID; copie con UUID, timestamp e contenuto invariati |
| Saturazione | 32/45; mancano esattamente i primi 13, contatore 13 |
| Sentinelle | Invariate in 399 letture; ricalcolati tutti i 10 hash delle tracce sintetiche |

Complessivamente: 16 richieste locali, 232 righe, 222 ID/UUID unici e 98.000 byte di body. Tutti gli stati indicano `local_loopback`, senza campi del registro cloud. Il controllo Android indipendente mostra PID 2633→2766 e contatore 1→2 nello stesso avvio del sistema.

In ciascuno dei 10 casi il codice nativo ha restituito **14 flag veri: 13 controlli più `all_passed`**. I sette controlli aggiunti verificano quattro casi aritmetici del budget e tre classificazioni della risposta. Sono helper eseguiti realmente su Android; **non esercitano** configurazione privata, prenotazione SQLite del budget cloud, HTTPS, quota o lettura PostHog.

Prima del commit della revoca il consenso precedente viene recuperato e i 20 eventi arrivano: questa osservazione non è conteggiata come revoca accettata. Nella prova in-flight, 10 eventi erano già ricevuti prima della revoca; nessun ulteriore invio è stato osservato nella finestra finale.

Il perimetro resta limitato a force-stop nei cutpoint nominati e raggiungibilità tramite `adb reverse`, non radio reali, spegnimento fisico o ogni possibile guasto. L'ordine tra file dipende anche dal flusso verificato del harness. Non sono provati consumi, RAM, saturazione in byte, comportamento GPS/Bluetooth, cloud o deduplicazione cloud. La prova overflow non include un riavvio dopo lo scarto: la persistenza del relativo contatore dopo riavvio resta non attestata.

**Privacy del bundle pubblico:** controllati tutti i 108 file; nessuna credenziale non redatta, identità personale o IP non loopback rilevato. I 16 campi del token fittizio sono redatti; gli altri identificatori sono sintetici o tecnici del laboratorio. Il controllo combina scansione dei contenuti e verifica dello schema, senza estendere l'esito a log privati o dati cloud.

Evidenze: [ricalcolo completo](independent-runtime-review.json), [script riproducibile](recompute_direct_review.py), [lifecycle](independent-lifecycle.json), [controllo privacy](privacy-review.json).
