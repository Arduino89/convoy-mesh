# Full Android sender — local HTTP verification

7 novembre 2026. Mandato Cama: correzione d93b309 accettata nel perimetro offline; verificare il mittente completo contro il solo ricevitore locale, senza altri invii PostHog o ritentativi dei vecchi20. PR5draft, Convoy invariata. **Run17 SUCCESS sul mittente completo**, senza nuovi invii PostHog. Revisione indipendente delle ricevute passata.

Riutilizzati controllo Android e dieci scenari ci_direct (revoca e interruzioni, nuovo consenso, rifiuto, normale offline/riavvio, retry con UUID, saturazione, richiesta già in volo). Il ricevitore ora risponde Ok mantenendo il verificatore privacy. La lettura HTTP200 è condivisa fra locale e cloud; nessun endpoint configurabile introdotto.

Sei prove aggiuntive:25righe con due barriere della conferma (prima25intatte, dopo primaACKesattamente5originali); quota, JSON malformato, UTF8invalido, risposta sconosciuta e corpoHTTP200troncato. Nei rifiuti: categoria fresca, coda stabilizzata senza route, stessa impronta SQLite e zeroACK, riavvio offline conservato, successivoOk e dueACK. Le identità/UUID/timestamp/digest degli item osservati permettono controllo indipendente dei ritentativi, senza parlare di deduplicazione cloud.

[Contratto e governance](plan.json). Ingresso `bash tools/telemetry_spike/run_ci_full_sender.sh`, toolchain esistente SDK36/build-tools36.0.0/JDK17/API35. Budget PostHog0; nessun segreto/progetto cloud caricato. Barriera radio/defaultnetwork prima/dopo, processo fermo e route rimossa prima del ripristino. Il bootstrap runner usa rete e il mittente usa solo ADBloopback. Test host e prove Android restano distinti.

## Risultati e provenienza

Sorgente compilato `50386a5c8ce5b0cf628073989a0eaf1549008e79`, wrapper `21938337ca1ac00ecd35697d16f592a62fa7477e`. [Run42389745788 / numero17 / tentativo1 / job128454627737](https://github.com/Arduino89/convoy-mesh/actions/runs/42389745788/job/128454627737): **SUCCESS**. Controllo Android8/8 prima del LAB;205/205testhost inCI, nessuno saltato. Il singolo skip della shell osservato sullo host locale non è presente nel runner.

| Prova Android reale | Esito osservato |
|---|---|
| Lotto25, due risposte trattenute |25righe prima della conferma;5righe originali dopo primaOk/ACK1;0dopo secondaOk/ACK2 |
| Quota / sconosciuta / JSON malformato / UTF8invalido |25righe identiche e0ACK dopo rifiuto completato e riavvio offline; recuperoOk25righe/2ACK |
| HTTP200 con corpo più corto del Content-Length |RESPONSE_READ_FAILED; stessa conservazione25/0ACK e successivo recupero |
| Normale offline e riavvio |100ricevuti,0mancanti/duplicati |
| Revoca accettata e tre interruzioni dopo intento durevole |80revocati complessivi,0riapparsi; nuovi consegnati, tracce/impostazioni sintetiche conservate |
| Rifiuto, ritentativo, saturazione |30rifiutati assenti; retry10conUUIDinvariati e duplicati locali visibili;13perdite da saturazione esplicite |
| Prima dell'intento durevole / già in volo |Confini osservati separatamente: revoca non ancora accettata / byte già ricevuti non richiamabili |
| Privacy e cleanup |Audit finale conforme; radio/defaultnetworkoff, processo fermo/routeADB rimossa, radio iniziali ripristinate |

Dieci scenari ereditati:9PASSED e1BOUNDARY_OBSERVED intenzionale prima dell'intento durevole. Sei casiHTTP nuovi:6PASS. Le impronte SQLite comprendono ID, generazione, event_id, body e bytes; il digest della coda residua è confrontato con il lotto originale. La prova compatta dei retry deriva dagli item effettivamente osservati, con UUID/timestamp/digestJSONcanonico; non viene descritta come deduplicazione cloud o identità dei byte dell'intera richiestaHTTP.

APKLAB eseguita: `com.cama.telemetry.direct_lab`,1.0/code1,min24/target36,49.555byte. SHA256 `3a213b3f47204a0a780611cc38986bfbd57334d67e5386ae3be647507c79ac46`; certificatoSHA256 `c7b1dad8ee642d6e1942e0035ba98089095846144a85476371ffbadf0bf8968c`. Compilata da50386a5 conSDK36/build-tools36.0.0/JDK17. Permessi INTERNET e ACCESS_NETWORK_STATE; nessuna configurazione/credenziale cloud caricata. Identità/firma controllate dagli strumenti nel runner, APKnon distribuita né scaricata indipendentemente. Le ricevute control/build complete sono nell'archivio sintetico.

## Ricalcolo senza Android o rete

L'archivio originale del job,93.180byte/SHA256 `b4786dbf8c4b87745545316cbe8b392f42e4180215ef4a15c0855b0de4ab4a03`, è salvato una sola volta come `inherited-evidence.b64`, senza duplicare108fileJSON. Solo ricevute e dati sintetici minimizzati, nessun log diagnostico integrale o APK. `full-result.json` contiene i sei nuovi casi,154.942byte/SHA256 `94f69fa092d12f1b07f9b3d508d95e097588648254b0cd6ebcf15c007a8c0450`.

Da questa cartella:

```bash
python3 decode_archive.py inherited-evidence.b64 decoded
python3 verify_runtime_evidence.py full-result.json decoded
```

Entrambi usano soltanto la libreria standard. Il decoder controlla hash dell'archivio, percorsi e digest di ogni file; il verificatore indipendente ricostruisce le coorti, confronta le osservazioni SQLite/UUID/digest e le ricevute runtime. [Riepilogo](summary.json), [review sorgenti](independent-source-review.json), [review workflow](independent-workflow-review.json).

Questa prova chiude il percorso locale del lettore HTTP, compresi InputStream/UTF8 e corpo interrotto. **Non prova TLS, ricezione/revoca/deduplicazione PostHog, privacy dell'intera infrastruttura o consumi/OEM sui telefoni.** Il risultato cloud storico resta20ricevuti/100in coda, corpo risposta sconosciuto. Nessuna sua riga è stata ricaricata o ritentata. [Proposta cloud160, da approvare](cloud-proposal.md); attualmente0autorizzati e vecchio plafond700chiuso.

[Revisione runtime indipendente](independent-runtime-review.json): export recuperati dal job autonomamente, ricostruzione identica e due ricalcoli identici anche sul pacchetto pubblico. [Ripristino verificato indipendentemente](independent-restoration-review.json) su `b3bfaf8fbc2c84e4ec7bbfe77093668be12c8f3e`: workflow originale identico byte per byte, codice compilato invariato e ultimo run ancora17, nessuna esecuzione ulteriore osservata. La ricevuta finale successiva cambia solo documentazione; il campo pending nella review runtime è storico e chiuso da questa review separata.
