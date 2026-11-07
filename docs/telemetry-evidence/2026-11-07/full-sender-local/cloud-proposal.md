# Proposta non esecutiva — successiva verifica cloud

Stato: DA APPROVARE. Nessun invio autorizzato da questo documento.

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
