# Full Android sender — local HTTP verification

7 novembre 2026. Mandato Cama: correzione d93b309 accettata nel perimetro offline; verificare il mittente completo contro il solo ricevitore locale, senza altri invii PostHog o ritentativi dei vecchi20. PR5draft, Convoy invariata. Android ancora da eseguire sul nuovo sorgente.

Riutilizzati controllo Android e dieci scenari ci_direct (revoca e interruzioni, nuovo consenso, rifiuto, normale offline/riavvio, retry con UUID, saturazione, richiesta già in volo). Il ricevitore ora risponde Ok mantenendo il verificatore privacy. La lettura HTTP200 è condivisa fra locale e cloud; nessun endpoint configurabile introdotto.

Sei prove aggiuntive:25righe con due barriere della conferma (prima25intatte, dopo primaACKesattamente5originali); quota, JSON malformato, UTF8invalido, risposta sconosciuta e corpoHTTP200troncato. Nei rifiuti: categoria fresca, coda stabilizzata senza route, stessa impronta SQLite e zeroACK, riavvio offline conservato, successivoOk e dueACK. Le identità/UUID/timestamp/digest degli item osservati permettono controllo indipendente dei ritentativi, senza parlare di deduplicazione cloud.

[Contratto e governance](plan.json). Ingresso `bash tools/telemetry_spike/run_ci_full_sender.sh`, toolchain esistente SDK36/build-tools36.0.0/JDK17/API35. Budget PostHog0; nessun segreto/progetto cloud caricato. Barriera radio/defaultnetwork prima/dopo, processo fermo e route rimossa prima del ripristino. Il bootstrap runner usa rete e il mittente usa solo ADBloopback. Test host e prove Android restano distinti.
