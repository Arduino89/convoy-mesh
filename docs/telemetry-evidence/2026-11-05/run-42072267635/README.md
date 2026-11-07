# Preparazione offline corretta — run42072267635

Sorgente diagnostico `e094db2d815b10aca3ce49cdd9007304818220b3`, numero13/tentativo1, job127403084581, SUCCESS. App LAB compilata dal sorgente invariato `2d76100fda1df0637e953f4ad90f26073028880c`. Il controllo Android precede installazione e preparazione; nessuna attività LAB o cloud viene avviata.

`result.json` è l’export sanitizzato originale, legato a bytes/SHA256in `export-manifest.json`. Le due ricevute originali controllo/build sono ricostruite dalla stampa ordinata del job con la serializzazione fissata dal codice e coincidono con i riferimenti SHA256. Nessun APK, stdin, credenziale, output CLI o dump di rete grezzo incluso. `workflow-executed.yml` è la definizione esatta dell’esecuzione, conservata prima di ripristinare il workflow originale;SHA256f6ad935df4eeb4d1583624435a11f336092ad579e4c057cb78729a44120634c9.

## Ricalcolo indipendente, senza Android né rete

Dalla radice del repository, con Python3e sola libreria standard:

```sh
python3 docs/telemetry-evidence/2026-11-05/run-42072267635/recompute_provision_review.py docs/telemetry-evidence/2026-11-05/run-42072267635 --out /tmp/convoy-provision-review.json
```

L’output deve essere byte-identico a `independent-review.json`. Il verificatore non importa i classificatori del produttore, non legge variabili d’ambiente e non accede ad ADB o provider. Controlla le ricevute dei quattro file sicuri, non rilegge il file privato o il binario APK già rimossi dal runner; mode600e byteidentici sono oracoli runtime del sorgente revisionato. Il risultato non è una seconda esecuzione Android.

## Limite di autorizzazione

Nove passaggi riusciti, rete assente prima/dopo, file verificato e pulito. Il budget storico conserva tutti i contatori sconosciuti,500conteggiati prudenzialmente e0disponibili. La prova fittizia non recupera il vecchio ledger né concede nuovo budget. App/telemetria/cloud, consumi e telefoni rimangono fuori da questa prova. Le regressioni native/locali precedenti sono conservate per sorgenti invariati.
