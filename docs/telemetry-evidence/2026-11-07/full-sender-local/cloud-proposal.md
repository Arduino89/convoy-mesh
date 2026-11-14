# Proposta non esecutiva — successiva verifica cloud

Stato: **TETTO APPROVATO DA CAMA IL 14-11-2026; PREFLIGHT E LANCIO NON ANCORA APPROVATI DAL GATE ESEGUIBILE**. Autorizzata una sola prova sintetica sul progetto PostHog EU esistente, massimo 160 trasmissioni comprensive di ogni retry/incertezza, nessuna attivazione a pagamento, nessun dato personale reale. Nessun invio autorizzato dalla sola presenza di questo documento: controlli e vincolo run/attempt/sorgente devono passare prima dell'esecuzione.

### Controlli consultati il 14 novembre 2026 (lettura live)

- CI GitHub [run #19](https://github.com/Arduino89/convoy-mesh/actions/runs/43613462960) / tentativo 1 / sorgente `dddcc57eb47c0f0b9a890cb554d3a581c63d91e6`: **SUCCESS** per test host e laboratorio Android locale; provisioning cloud **SKIPPED**. Il documento aggiornato non è sorgente eseguito nel run #19.
- PostHog progetto **330212**, ingestione `https://eu.i.posthog.com`: `anonymize_ips=true`, `session_recording_opt_in=false`, `is_pending_deletion=false`.
- Piano **free**, senza abbonamento attivo; analytics: **182 eventi correnti su 1.000.000 inclusi** alla lettura, soglia non superata. Questo non garantisce che lo stato resti invariato al momento del run: ricontrollare.
- Eventi: retention predefinita **12 mesi**, `project_retention_months=null`; cancellazione periodica secondo il piano. Non dichiarare attiva una retention di 30 giorni: per una futura beta è solo una preferenza non configurata.
- L'app PostHog espone `persons-bulk-delete` per cancellare persone ed eventualmente eventi, **ma non è stata effettuata alcuna cancellazione o prova end-to-end**. Il gate `deletion` resta **UNVERIFIED** finché non esiste evidenza pertinente. Non segnare VERIFIED basandosi sulla sola esistenza dell'API.
- Il verificatore statico di launch `review_cloud_launch.py`, dal commit `dddcc57`, impone **700+160=860** e rifiuta l'allowance storica 500+200. Il workflow reale è ancora nel suo assetto sicuro di default, senza attivazione cloud su push; prima di ogni run verificare lo SHA esatto, i controlli fresh e la singola opportunità di dispatch, senza autopromozione.

**Decisione operativa: HOLD, zero invii cloud nel presente checkpoint.** Terminare prima la verifica del gate cancellazione, preflight appena aggiornato, pin del sorgente e workflow a esecuzione unica, con verifica indipendente e senza creare nuove autorizzazioni di spesa o distribuzione.

Riutilizzare lo stesso laboratorio, progetto PostHog EU e segreto GitHub già esistenti. Nessun SDK, servizio o integrazione Convoy aggiuntivi. Usare un emulatore nuovo e identificativi sintetici nuovi: i vecchi 20 eventi restano esclusi.

| Scenario | Eventi unici | Trasmissioni nominali |
|---|---:|---:|
| Offline → riavvio → rete | 100 | 100 |
| Revoca di 20 ancora offline; nuovo consenso e 10 nuovi | 10 consegnati; 20 revocati mai trasmessi | 10 |
| Conferma deliberatamente scartata e ritentativo con stessi UUID | 10 | 20 |
| Totale nominale | 120 ricevuti | 130 |

**Nuovo tetto proposto: 160 trasmissioni di eventi**, comprendendo i 130 nominali e 30 di margine (un lotto20 e uno10). Ogni prenotazione/tentativo incerto conta; nessun rimborso, azzeramento o riuso delle180 righe non usate della vecchia autorizzazione. Prudenziale precedente700 + proposta160 =860 cumulativo massimo, non eventi effettivamente ricevuti.

Una sola esecuzione/tentativo, senza rilancio automatico. Prima: aggiornare e revisionare il gate per il nuovo precedente700/aggiunta160/totale860 e l'esatto sorgente; il vecchio gate500+200 non è riutilizzabile. Ricontrollare modalità gratuita/quota, privacy e accesso ai soli dati LAB, preparazione privata, controllo Android, provenienza APK e regressioni locali ancora valide. Nessuna nuova spesa automatica.

Arresto immediato su blocco permanente, budget o ambiente non verificato; conservare le ricevute e contare prudenzialmente i tentativi incerti. Nessun flush per svuotare dati revocati. Confrontare letture raw e conteggi PostHog separati dalla conferma HTTP, senza DISTINCT o filtri che nascondano duplicati/eventi inattesi: normali100, revocati0, nuovi10 e ritentativi10 con identità invariate. Verificare deduplicazione cloud effettiva senza dedurla dagli UUID client.

Accessi necessari: runner pubblico e segreto di progetto già esistenti; lettura minimizzata di impostazioni/quota ed eventi LAB per il riscontro. Non mostrare token o leggere risposte API che li espongono. Nessuna nuova chiave, attivazione a pagamento o cancellazione proposta.

Restano esclusi merge, release, integrazione, utenti reali e prove fisiche di consumi/GPS/Bluetooth. **Budget attuale fino a nuova approvazione: zero**, compresi i vecchi20.
